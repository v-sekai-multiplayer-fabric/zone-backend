/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 K. S. Ernest (iFire) Lee */
#ifndef ARTIFACTS_MMO_H3_CLIENT_H
#define ARTIFACTS_MMO_H3_CLIENT_H

#ifdef __cplusplus
extern "C" {
#endif

/* Runs one authenticated HTTP/3 request to completion (connect, send,
 * receive, close) and returns the response body as a malloc'd,
 * NUL-terminated string the caller must free() - or NULL on failure.
 * See artifacts_mmo_h3_client.c for what this reuses vs. adds. */
char *artifacts_mmo_h3_request(const char *host, int port, const char *cert_root_pem,
	const char *method, const char *path, const char *bearer_token,
	const char *body);

#ifdef __cplusplus
}
#endif

#endif /* ARTIFACTS_MMO_H3_CLIENT_H */
