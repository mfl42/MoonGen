local vpp = require "vpp"

vpp.connect({
    socket_path = "/run/vpp/api.sock"
})

vpp.udp_send({
    src_ip = "10.0.0.1",
    dst_ip = "10.0.0.2",
    src_port = 12345,
    dst_port = 8080,
    payload = "hello over udp"
})

local session = vpp.tcp_connect({
    src_ip = "10.0.0.1",
    dst_ip = "10.0.0.2",
    src_port = 12346,
    dst_port = 80
})

vpp.tcp_send(session, "GET / HTTP/1.1\r\nHost: test\r\n\r\n")
vpp.tcp_close(session)
vpp.disconnect()
