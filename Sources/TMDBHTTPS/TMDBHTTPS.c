#include "TMDBHTTPS.h"

#include <curl/curl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t limit;
    TMDBHTTPSCancellation cancelled;
    void *context;
    TMDBHTTPSResponse *response;
} Transfer;

static pthread_once_t initialization = PTHREAD_ONCE_INIT;
static CURLcode initialization_result;

static void initialize_curl(void) {
    initialization_result = curl_global_init(CURL_GLOBAL_DEFAULT);
}

static size_t receive(char *data, size_t size, size_t count, void *context) {
    Transfer *transfer = context;
    TMDBHTTPSResponse *response = transfer->response;
    if (size != 0 && count > (transfer->limit - response->length) / size) {
        return 0;
    }
    size_t length = size * count;
    if (length == 0) {
        return 0;
    }
    uint8_t *buffer = realloc(response->bytes, response->length + length);
    if (buffer == NULL) {
        return 0;
    }
    memcpy(buffer + response->length, data, length);
    response->bytes = buffer;
    response->length += length;
    return length;
}

static int progress(void *context, curl_off_t total, curl_off_t received,
                    curl_off_t upload_total, curl_off_t sent) {
    Transfer *transfer = context;
    return transfer->cancelled(transfer->context);
}

int tmdb_https_get(const char *url, const char *resolve_rule, long timeout_ms,
                  size_t max_bytes, TMDBHTTPSCancellation cancelled, void *context,
                  TMDBHTTPSResponse *response) {
    *response = (TMDBHTTPSResponse){0};
    pthread_once(&initialization, initialize_curl);
    if (initialization_result != CURLE_OK) {
        return initialization_result;
    }

    CURL *curl = curl_easy_init();
    if (curl == NULL) {
        return CURLE_FAILED_INIT;
    }
    struct curl_slist *resolve = curl_slist_append(NULL, resolve_rule);
    CURLcode result = CURLE_OUT_OF_MEMORY;
    Transfer transfer = {max_bytes, cancelled, context, response};

    if (resolve != NULL) {
        // Override the socket address while keeping the original HTTPS name and TLS verification.
        result = CURLE_OK;
#define SET_OPTION(option, value) \
        if (result == CURLE_OK) { result = curl_easy_setopt(curl, option, value); }
        SET_OPTION(CURLOPT_URL, url);
        SET_OPTION(CURLOPT_PROTOCOLS_STR, "https");
        SET_OPTION(CURLOPT_PROXY, "");
        SET_OPTION(CURLOPT_RESOLVE, resolve);
        SET_OPTION(CURLOPT_TIMEOUT_MS, timeout_ms);
        SET_OPTION(CURLOPT_NOSIGNAL, 1L);
        SET_OPTION(CURLOPT_WRITEFUNCTION, receive);
        SET_OPTION(CURLOPT_WRITEDATA, &transfer);
        SET_OPTION(CURLOPT_NOPROGRESS, 0L);
        SET_OPTION(CURLOPT_XFERINFOFUNCTION, progress);
        SET_OPTION(CURLOPT_XFERINFODATA, &transfer);
#undef SET_OPTION
        if (result == CURLE_OK) {
            result = curl_easy_perform(curl);
        }
        if (result == CURLE_OK) {
            result = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response->status);
        }
    }
    curl_easy_cleanup(curl);
    curl_slist_free_all(resolve);
    return result;
}
