/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 K. S. Ernest (iFire) Lee */
/*
 * A real HTTP/3 client with a custom Authorization header, over the
 * vendored picoquic + picotls + mbedtls stack - the piece
 * picoquicdemo_client (this same directory) doesn't have: its scenario
 * format ("stream_id:doc_name") has no way to add extra headers, since
 * h3zero_client_create_stream_request_ex only ever encodes the
 * spec-required pseudo-headers (:method, :scheme, :path, :authority,
 * user-agent) - the same gap this session found in
 * v-sekai-multiplayer-fabric/fabric-godot-core's http3_client.cpp
 * (request()'s p_headers parameter is accepted but stubbed out).
 *
 * This does NOT modify any vendored file. It reuses:
 *  - picoquic_create / picoquic_create_cnx / picoquic_start_client_cnx
 *    (the same connection-setup calls picoquicdemo.c's quic_client()
 *    uses, trimmed of migration/multipath/0-RTT, none of which this
 *    one-shot authenticated GET/POST needs)
 *  - picoquic_demo_client_callback (democlient.c) UNCHANGED for
 *    receiving: it already parses HEADERS/DATA frames correctly against
 *    partial QUIC delivery and writes the body to a file - reimplementing
 *    that robustly would be redoing already-proven work for no reason.
 *  - h3zero_qpack_code_encode / h3zero_qpack_literal_plus_ref_encode
 *    (the same public QPACK primitives h3zero_create_request_header_frame_ex
 *    already calls) plus h3zero_qpack_literal_plus_name_encode - a fully
 *    literal name+value encoder already used elsewhere in h3zero.c for
 *    headers with no QPACK static-table entry (e.g. ":protocol") -
 *    "authorization" is exactly such a header.
 *
 * What's new here is only build_authenticated_request(): the frame
 * assembly (frame type byte, 1-or-3-byte varint length prefix, then the
 * standard pseudo-headers) mirrors h3zero_client_create_stream_request_ex
 * exactly, with one extra qpack field appended before the length is
 * patched in, and (for POST) the real JSON body bytes embedded directly
 * as a DATA frame in the same initial write (fin=1) - ArtifactsMMO
 * request bodies are small and fully known upfront, so there's no need
 * for the deferred prepare-to-send path picoquic_demo_client_open_stream
 * uses for large/streamed POST bodies.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <picoquic.h>
#include <picoquic_internal.h>
#include <picoquic_utils.h>
#include <picosocks.h>
#include <picoquic_packet_loop.h>
#include <h3zero.h>
#include <h3zero_common.h>
#include <democlient.h>

#include "artifacts_mmo_h3_client.h"

static uint8_t *build_authenticated_request(
    uint8_t *buffer, size_t max_bytes,
    const char *method, const char *path, const char *host,
    const char *bearer_token, const uint8_t *body, size_t body_len,
    size_t *consumed) {
	uint8_t *o_bytes = buffer;
	uint8_t *o_bytes_max = buffer + max_bytes;

	*consumed = 0;
	if (max_bytes < 3 || host == NULL) return NULL;

	*o_bytes++ = h3zero_frame_header;
	o_bytes += 2; /* reserve two bytes for frame length, patched below */

	if (strcmp(method, "POST") == 0) {
		o_bytes = h3zero_create_post_header_frame(o_bytes, o_bytes_max,
			(const uint8_t *)path, strlen(path), host, h3zero_content_type_json);
	} else {
		o_bytes = h3zero_create_request_header_frame_ex(o_bytes, o_bytes_max,
			(const uint8_t *)path, strlen(path), NULL, 0, host, H3ZERO_USER_AGENT_STRING);
	}

	/* The one thing neither vendored builder can do: a header with no
	 * QPACK static-table entry needs a literal name, not a reference. */
	if (o_bytes != NULL && bearer_token != NULL) {
		char auth_value[512];
		int n = snprintf(auth_value, sizeof(auth_value), "Bearer %s", bearer_token);
		if (n > 0 && (size_t)n < sizeof(auth_value)) {
			o_bytes = h3zero_qpack_literal_plus_name_encode(o_bytes, o_bytes_max,
				(const uint8_t *)"authorization", 13, (const uint8_t *)auth_value, (size_t)n);
		}
	}

	if (o_bytes == NULL) return NULL;

	{
		size_t header_length = o_bytes - &buffer[3];
		if (header_length < 64) {
			buffer[1] = (uint8_t)header_length;
			memmove(&buffer[2], &buffer[3], header_length);
			o_bytes--;
		} else {
			buffer[1] = (uint8_t)((header_length >> 8) | 0x40);
			buffer[2] = (uint8_t)(header_length & 0xFF);
		}
	}

	if (body != NULL && body_len > 0) {
		if (o_bytes + 1 + 8 > o_bytes_max) return NULL;
		*o_bytes++ = h3zero_frame_data;
		{
			size_t ll = picoquic_varint_encode(o_bytes, o_bytes_max - o_bytes, body_len);
			if (ll == 0) return NULL;
			o_bytes += ll;
		}
		if (o_bytes + body_len > o_bytes_max) return NULL;
		memcpy(o_bytes, body, body_len);
		o_bytes += body_len;
	}

	*consumed = o_bytes - buffer;
	return o_bytes;
}

typedef struct st_client_loop_ctx_t {
	picoquic_cnx_t *cnx_client;
	picoquic_demo_callback_ctx_t *demo_ctx;
	picoquic_demo_client_stream_ctx_t *my_stream;
	int notified_ready;
	int request_sent;
	int close_requested;
	const char *method;
	const char *path;
	const char *bearer_token;
	const uint8_t *body;
	size_t body_len;
	const char *response_path;
} client_loop_ctx_t;

static int send_authenticated_request(client_loop_ctx_t *lc) {
	uint8_t buffer[4096];
	size_t consumed = 0;
	uint8_t *end = build_authenticated_request(buffer, sizeof(buffer),
		lc->method, lc->path, lc->cnx_client->sni, lc->bearer_token,
		lc->body, lc->body_len, &consumed);
	if (end == NULL) {
		fprintf(stderr, "Failed to build the authenticated request.\n");
		return -1;
	}

	picoquic_demo_client_stream_ctx_t *stream_ctx =
		(picoquic_demo_client_stream_ctx_t *)malloc(sizeof(picoquic_demo_client_stream_ctx_t));
	if (stream_ctx == NULL) return -1;
	memset(stream_ctx, 0, sizeof(picoquic_demo_client_stream_ctx_t));
	stream_ctx->next_stream = lc->demo_ctx->first_stream;
	lc->demo_ctx->first_stream = stream_ctx;
	stream_ctx->stream_id = 0;
	stream_ctx->is_open = 1;
	if (!lc->demo_ctx->no_disk) {
		stream_ctx->f_name = picoquic_string_duplicate(lc->response_path);
	}
	lc->demo_ctx->nb_open_streams++;
	lc->demo_ctx->nb_client_streams++;
	lc->my_stream = stream_ctx;

	fprintf(stdout, "Sending authenticated %s %s (%zu bytes on the wire)\n",
		lc->method, lc->path, consumed);
	return picoquic_add_to_stream_with_ctx(lc->cnx_client, 0, buffer, consumed, 1, stream_ctx);
}

/* Shared state-machine check, run from every callback mode that can fire
 * without a fresh incoming packet (after_send, time_check) as well as
 * after_receive - picoquic_close() starts a graceful drain that doesn't
 * necessarily produce another inbound packet to hang after_receive off
 * of, so termination has to be checked on the timer-driven paths too. */
static int advance_state_machine(client_loop_ctx_t *lc) {
	if (lc->demo_ctx->connection_closed || picoquic_get_cnx_state(lc->cnx_client) == picoquic_state_disconnected) {
		fprintf(stdout, "The connection is closed!\n");
		return PICOQUIC_NO_ERROR_TERMINATE_PACKET_LOOP;
	}
	if (!lc->notified_ready &&
		picoquic_get_cnx_state(lc->cnx_client) == picoquic_state_client_almost_ready) {
		if (lc->cnx_client->alpn != NULL) {
			fprintf(stdout, "Negotiated ALPN: %s\n", lc->cnx_client->alpn);
		}
		lc->notified_ready = 1;
	} else if (!lc->request_sent &&
		(picoquic_get_cnx_state(lc->cnx_client) == picoquic_state_ready ||
		 picoquic_get_cnx_state(lc->cnx_client) == picoquic_state_client_ready_start)) {
		lc->request_sent = 1;
		if (send_authenticated_request(lc) != 0) {
			return PICOQUIC_NO_ERROR_TERMINATE_PACKET_LOOP;
		}
	} else if (lc->request_sent && !lc->close_requested &&
		lc->my_stream != NULL && !lc->my_stream->is_open) {
		/* picoquic_demo_client_callback (democlient.c) already closed our
		 * stream on FIN - the response is fully received and written to
		 * disk. Nothing else is outstanding, so ask picoquic to close the
		 * connection; the loop then exits once it reports disconnected. */
		fprintf(stdout, "Response received - closing the connection.\n");
		lc->close_requested = 1;
		picoquic_close(lc->cnx_client, 0);
	}
	return 0;
}

static int client_loop_cb(picoquic_quic_t *quic, picoquic_packet_loop_cb_enum cb_mode,
	void *callback_ctx, void *callback_arg) {
	(void)quic;
	client_loop_ctx_t *lc = (client_loop_ctx_t *)callback_ctx;
	if (lc == NULL) return PICOQUIC_ERROR_UNEXPECTED_ERROR;

	switch (cb_mode) {
	case picoquic_packet_loop_ready: {
		picoquic_packet_loop_options_t *options = (picoquic_packet_loop_options_t *)callback_arg;
		options->do_system_call_duration = 1;
		fprintf(stdout, "Waiting for packets.\n");
		break;
	}
	case picoquic_packet_loop_after_receive:
	case picoquic_packet_loop_after_send:
	case picoquic_packet_loop_time_check:
		return advance_state_machine(lc);
	default:
		break;
	}
	return 0;
}

/* The reusable entry point: runs one authenticated request to completion
 * and returns the response body (read back from the file
 * picoquic_demo_client_callback wrote it to - reusing that proven
 * receive path rather than accumulating bytes in memory ourselves).
 * Not thread-safe / not reentrant across concurrent calls (a fixed
 * per-call temp file name) - fine for this agent's one-request-at-a-time
 * usage; a concurrent caller would need a unique name per call. */
char *artifacts_mmo_h3_request(const char *host, int port, const char *cert_root_pem,
	const char *method, const char *path, const char *bearer_token,
	const char *body) {
	char *result = NULL;
	const char *response_path = "artifacts_mmo_h3_response.bin";

#ifdef _WINDOWS
	WSADATA wsaData;
	(void)WSA_START(MAKEWORD(2, 2), &wsaData);
#endif

	struct sockaddr_storage server_address;
	int is_name = 0;
	if (picoquic_get_server_address(host, port, &server_address, &is_name) != 0) {
		fprintf(stderr, "Cannot resolve %s:%d\n", host, port);
		return NULL;
	}

	uint8_t reset_seed[PICOQUIC_RESET_SECRET_SIZE];
	memset(reset_seed, 0x42, sizeof(reset_seed));
	uint64_t current_time = picoquic_current_time();

	picoquic_quic_t *qclient = picoquic_create(1, NULL, NULL, cert_root_pem, "h3",
		NULL, NULL, NULL, NULL, reset_seed, current_time, NULL, NULL, NULL, 0);
	if (qclient == NULL) {
		fprintf(stderr, "picoquic_create failed.\n");
		return NULL;
	}

	picoquic_cnx_t *cnx_client = picoquic_create_cnx(qclient,
		picoquic_null_connection_id, picoquic_null_connection_id,
		(struct sockaddr *)&server_address, current_time, 0, host, "h3", 1);
	if (cnx_client == NULL) {
		fprintf(stderr, "picoquic_create_cnx failed.\n");
		picoquic_free(qclient);
		return NULL;
	}

	picoquic_demo_callback_ctx_t demo_ctx = {0};
	picoquic_demo_client_initialize_context(&demo_ctx, NULL, 0, "h3", 0, 0);
	demo_ctx.out_dir = ".";

	picoquic_set_callback(cnx_client, picoquic_demo_client_callback, &demo_ctx);
	cnx_client->grease_transport_parameters = 1;
	cnx_client->local_parameters.enable_time_stamp = 3;

	if (picoquic_start_client_cnx(cnx_client) != 0) {
		fprintf(stderr, "picoquic_start_client_cnx failed.\n");
		picoquic_demo_client_delete_context(&demo_ctx);
		picoquic_free(qclient);
		return NULL;
	}

	client_loop_ctx_t lc = {0};
	lc.cnx_client = cnx_client;
	lc.demo_ctx = &demo_ctx;
	lc.method = method;
	lc.path = path;
	lc.bearer_token = bearer_token;
	lc.body = (const uint8_t *)body;
	lc.body_len = body ? strlen(body) : 0;
	lc.response_path = response_path;

	picoquic_packet_loop_param_t param = {0};
	param.local_af = server_address.ss_family;

	int ret = picoquic_packet_loop_v2(qclient, &param, client_loop_cb, &lc);
	fprintf(stdout, "Client exit with code = %d\n", ret);

	if (ret == 0) {
		FILE *f = picoquic_file_open(response_path, "rb");
		if (f != NULL) {
			fseek(f, 0, SEEK_END);
			long len = ftell(f);
			fseek(f, 0, SEEK_SET);
			if (len >= 0) {
				result = (char *)malloc((size_t)len + 1);
				if (result != NULL) {
					size_t n = fread(result, 1, (size_t)len, f);
					result[n] = '\0';
				}
			}
			fclose(f);
			remove(response_path);
		}
	}

	picoquic_demo_client_delete_context(&demo_ctx);
	picoquic_free(qclient);
	return result;
}

/* This file is also linked into s7agent (artifacts_mmo_h3_request() is
 * the reusable entry point that FFI wraps) - define
 * ARTIFACTS_MMO_H3_CLIENT_NO_MAIN there to avoid a duplicate main(). */
#ifndef ARTIFACTS_MMO_H3_CLIENT_NO_MAIN
int main(int argc, char **argv) {
	if (argc < 6) {
		fprintf(stderr, "usage: %s host port cert_root.pem GET|POST path [body]\n", argv[0]);
		fprintf(stderr, "  bearer token is read from ARTIFACTS_MMO_APIKEY\n");
		return 1;
	}
	const char *host = argv[1];
	int port = atoi(argv[2]);
	const char *cert_root = argv[3];
	const char *method = argv[4];
	const char *path = argv[5];
	const char *body = (argc > 6) ? argv[6] : NULL;
	const char *token = getenv("ARTIFACTS_MMO_APIKEY");
	if (token == NULL) {
		fprintf(stderr, "ARTIFACTS_MMO_APIKEY is not set.\n");
		return 1;
	}

	char *response = artifacts_mmo_h3_request(host, port, cert_root, method, path, token, body);
	if (response == NULL) {
		fprintf(stderr, "Request failed.\n");
		return 1;
	}
	fputs(response, stdout);
	fputc('\n', stdout);
	free(response);
	return 0;
}
#endif /* ARTIFACTS_MMO_H3_CLIENT_NO_MAIN */
