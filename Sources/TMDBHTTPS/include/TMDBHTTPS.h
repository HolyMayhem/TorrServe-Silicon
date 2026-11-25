#ifndef TORRSERVE_TMDB_HTTPS_H
#define TORRSERVE_TMDB_HTTPS_H

#include <stddef.h>
#include <stdint.h>

typedef int (*TMDBHTTPSCancellation)(void *context);

typedef struct {
    uint8_t *bytes;
    size_t length;
    long status;
} TMDBHTTPSResponse;

// The caller owns response.bytes and must free it, including on failure.
int tmdb_https_get(const char *url, const char *resolve_rule, long timeout_ms,
                  size_t max_bytes, TMDBHTTPSCancellation cancelled, void *context,
                  TMDBHTTPSResponse *response);

#endif
