package.path = package.path .. ";./lua/?.lua"

local vpp = require "vpp"
local env = require "vmoongen-env"
local sock = env.vpp_socket()

print(vpp.show_version(sock))
print(vpp.show_interfaces(sock))
print(vpp.show_plugins(sock))
print(vpp.show_sessions(sock, "summary"))
print(vpp.set_interface_state(sock, "local0", "up"))
print(vpp.show_interfaces(sock))
print(vpp.set_interface_state(sock, "local0", "down"))
print(vpp.show_interfaces(sock))
