package.path = package.path .. ";./lua/?.lua"

local vpp = require("vpp_socket")
local env = require "vmoongen-env"

local bridge_socket = env.bridge_socket()
local vpp_socket = env.vpp_socket()

print(vpp.show_version(bridge_socket, vpp_socket))
print(vpp.show_interfaces(bridge_socket, vpp_socket))
print(vpp.show_sessions(bridge_socket, vpp_socket, "summary"))
