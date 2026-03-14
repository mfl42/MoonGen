#include "vpp_adapter.h"

#include <stdio.h>
#include <string.h>

int vpp_init(vpp_context_t* ctx, const vpp_config_t* cfg) {
    if (!ctx) {
        return -1;
    }

    memset(ctx, 0, sizeof(*ctx));

    if (cfg && cfg->socket_path) {
        printf("[vpp] init with socket: %s\n", cfg->socket_path);
    } else {
        printf("[vpp] init with default socket\n");
    }

    return 0;
}

int vpp_connect(vpp_context_t* ctx) {
    if (!ctx) {
        return -1;
    }

    ctx->connected = 1;
    printf("[vpp] connected\n");
    return 0;
}

int vpp_disconnect(vpp_context_t* ctx) {
    if (!ctx) {
        return -1;
    }

    ctx->connected = 0;
    printf("[vpp] disconnected\n");
    return 0;
}

int vpp_udp_send(vpp_context_t* ctx,
                 const char* src_ip,
                 const char* dst_ip,
                 int src_port,
                 int dst_port,
                 const char* payload) {
    if (!ctx || !ctx->connected) {
        return -1;
    }

    printf("[vpp] udp send %s:%d -> %s:%d payload='%s'\n",
           src_ip ? src_ip : "0.0.0.0",
           src_port,
           dst_ip ? dst_ip : "0.0.0.0",
           dst_port,
           payload ? payload : "");
    return 0;
}

int vpp_tcp_connect(vpp_context_t* ctx,
                    const char* src_ip,
                    const char* dst_ip,
                    int src_port,
                    int dst_port) {
    if (!ctx || !ctx->connected) {
        return -1;
    }

    printf("[vpp] tcp connect %s:%d -> %s:%d\n",
           src_ip ? src_ip : "0.0.0.0",
           src_port,
           dst_ip ? dst_ip : "0.0.0.0",
           dst_port);

    return 1;
}

int vpp_tcp_send(vpp_context_t* ctx, int session_id, const char* payload) {
    if (!ctx || !ctx->connected) {
        return -1;
    }

    printf("[vpp] tcp send session=%d payload='%s'\n",
           session_id,
           payload ? payload : "");
    return 0;
}

int vpp_tcp_close(vpp_context_t* ctx, int session_id) {
    if (!ctx || !ctx->connected) {
        return -1;
    }

    printf("[vpp] tcp close session=%d\n", session_id);
    return 0;
