#ifndef VPP_ADAPTER_H
#define VPP_ADAPTER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char* socket_path;
} vpp_config_t;

typedef struct {
    int connected;
} vpp_context_t;

int vpp_init(vpp_context_t* ctx, const vpp_config_t* cfg);
int vpp_connect(vpp_context_t* ctx);
int vpp_disconnect(vpp_context_t* ctx);

int vpp_udp_send(vpp_context_t* ctx,
                 const char* src_ip,
                 const char* dst_ip,
                 int src_port,
                 int dst_port,
                 const char* payload);

int vpp_tcp_connect(vpp_context_t* ctx,
                    const char* src_ip,
                    const char* dst_ip,
                    int src_port,
                    int dst_port);

int vpp_tcp_send(vpp_context_t* ctx, int session_id, const char* payload);
int vpp_tcp_close(vpp_context_t* ctx, int session_id);

#ifdef __cplusplus
}
#endif

#endif

