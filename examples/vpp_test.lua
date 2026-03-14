package.path = package.path .. ";./lua/?.lua"

local vpp = require "vpp"

local result = vpp.run_cli(
    "/home/mfl42/Projects/vpp/run/cli.sock",
    "show version"
)

print(result)
