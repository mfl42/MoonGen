package.path = package.path .. ";./lua/?.lua"

local vpp = require("vpp_socket")

local bridge_socket = "/tmp/vmoongen.sock"
local vpp_socket = "/home/mfl42/Projects/vpp/run/cli.sock"

print(vpp.show_version(bridge_socket, vpp_socket))
print(vpp.show_interfaces(bridge_socket, vpp_socket))
print(vpp.show_sessions(bridge_socket, vpp_socket))
