package.path = package.path .. ";./lua/?.lua"

local vpp = require "vpp"

vpp.connect({
    socket_path = "/run/vpp/api.sock"
})

vpp.install_profile({
    name = "http_million",
    protocol = "tcp",
    clients = "10.0.0.0/16",
    servers = {
        { ip = "192.0.2.10", port = 80 },
        { ip = "192.0.2.11", port = 80 }
    },
    cps = 50000,
    duration_s = 60,
    payload = "GET / HTTP/1.1\r\nHost: test\r\n\r\n",
    close_mode = "graceful",
    stats_interval_ms = 1000
})

vpp.list_profiles()
vpp.start_profile("http_million")
vpp.get_profile_stats("http_million")
vpp.stop_profile("http_million")
vpp.get_profile_stats("http_million")
vpp.remove_profile("http_million")
vpp.disconnect()
