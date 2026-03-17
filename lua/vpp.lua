local vpp = {}
local env = require "vmoongen-env"
local socket_vpp = require "vpp_socket"

local function bridge_socket()
    return env.bridge_socket()
end

local function resolve_vpp_socket(socket_path)
    return socket_path or env.vpp_socket()
end

function vpp.run_cli(socket_path, command)
    if command == nil then
        command = socket_path
        socket_path = nil
    end
    assert(command, "command required")

    return socket_vpp.run_cli(bridge_socket(), resolve_vpp_socket(socket_path), command)
end

function vpp.show_version(socket_path)
    return socket_vpp.show_version(bridge_socket(), resolve_vpp_socket(socket_path))
end

function vpp.show_interfaces(socket_path)
    return socket_vpp.show_interfaces(bridge_socket(), resolve_vpp_socket(socket_path))
end

function vpp.show_plugins(socket_path)
    return socket_vpp.show_plugins(bridge_socket(), resolve_vpp_socket(socket_path))
end

function vpp.show_sessions(socket_path, detail)
    return socket_vpp.show_sessions(bridge_socket(), resolve_vpp_socket(socket_path), detail)
end

function vpp.set_interface_state(socket_path, interface, state)
    if state == nil then
        state = interface
        interface = socket_path
        socket_path = nil
    end
    assert(interface, "interface required")
    assert(state, "state required")

    return socket_vpp.set_interface_state(bridge_socket(), resolve_vpp_socket(socket_path), interface, state)
end

return vpp
