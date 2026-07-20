/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 K. S. Ernest (iFire) Lee */
/* Creates and frees a client-only picoquic_quic_t (no cert/key: those are
 * only for server mode). Proves the vendored stack compiles, links, and
 * its core create/free API works. No sockets, no handshake, no Flow. */

#include "picoquic.h"

#include <stdio.h>
#include <string.h>

int main(void) {
	uint8_t reset_seed[PICOQUIC_RESET_SECRET_SIZE];
	memset(reset_seed, 0x42, sizeof(reset_seed));

	picoquic_quic_t *quic = picoquic_create(
			8,                 /* max_nb_connections */
			NULL, NULL, NULL,  /* cert/key/root: none, client-only context */
			NULL,              /* default_alpn */
			NULL, NULL,        /* default_callback_fn, default_callback_ctx */
			NULL, NULL,        /* cnx_id_callback, cnx_id_callback_data */
			reset_seed,
			picoquic_current_time(),
			NULL,              /* p_simulated_time */
			NULL, NULL, 0);    /* ticket_file_name, ticket_encryption_key, length */

	if (quic == NULL) {
		fprintf(stderr, "FAIL: picoquic_create returned NULL\n");
		return 1;
	}

	picoquic_free(quic);
	printf("OK: picoquic_create/picoquic_free round-tripped\n");
	return 0;
}
