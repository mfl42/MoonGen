package.path = package.path .. ";./lua/?.lua"

local vpp = require "vpp"
local env = require "vmoongen-env"

local result = vpp.run_cli(
    env.vpp_socket(),
    "show version"
)

print(result)
