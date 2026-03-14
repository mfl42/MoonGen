local vpp = {}

function vpp.connect(opts)
    opts = opts or {}
    print("[lua/vpp] connect socket=" .. (opts.socket_path or "/run/vpp/api.sock"))
    return true
end

function vpp.disconnect()
    print("[lua/vpp] disconnect")
    return true
end

function vpp.udp_send(opts)
    assert(opts, "opts required")
    print(string.format(
        "[lua/vpp] udp_send %s:%d -> %s:%d payload=%s",
        opts.src_ip or "0.0.0.0",
        opts.src_port or 0,
        opts.dst_ip or "0.0.0.0",
        opts.dst_port or 0,
        opts.payload or ""
    ))
    return true
end

function vpp.tcp_connect(opts)
    assert(opts, "opts required")
    print(string.format(
        "[lua/vpp] tcp_connect %s:%d -> %s:%d",
        opts.src_ip or "0.0.0.0",
        opts.src_port or 0,
        opts.dst_ip or "0.0.0.0",
        opts.dst_port or 0
    ))
    return 1
end

function vpp.tcp_send(session_id, payload)
    print(string.format("[lua/vpp] tcp_send session=%d payload=%s", session_id or -1, payload or ""))
    return true
end

function vpp.tcp_close(session_id)
    print(string.format("[lua/vpp] tcp_close session=%d", session_id or -1))
    return true
end

