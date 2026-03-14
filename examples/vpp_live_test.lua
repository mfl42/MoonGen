package.path = package.path .. ";./lua/?.lua"

local vpp = require "vpp"
local sock = "/home/mfl42/Projects/vpp/run/cli.sock"

print(vpp.show_version(sock))
print(vpp.show_interfaces(sock))
print(vpp.show_plugins(sock))
print(vpp.show_sessions(sock))
print(vpp.set_interface_state(sock, "local0", "up"))
print(vpp.show_interfaces(sock))
print(vpp.set_interface_state(sock, "local0", "down"))
print(vpp.show_interfaces(sock))
