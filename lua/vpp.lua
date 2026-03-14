local vpp = {}

local function shell_quote(s)
    s = tostring(s or "")
    s = s:gsub("'", "'\"'\"'")
    return "'" .. s .. "'"
end

local function json_escape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function is_array(tbl)
    local max = 0
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        if k > max then
            max = k
        end
        count = count + 1
    end
    return max == count
end

local function encode_json(value)
    local t = type(value)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        return '"' .. json_escape(value) .. '"'
    elseif t == "table" then
        if is_array(value) then
            local items = {}
            for i = 1, #value do
                items[#items + 1] = encode_json(value[i])
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            local items = {}
            for k, v in pairs(value) do
                items[#items + 1] = '"' .. json_escape(k) .. '":' .. encode_json(v)
            end
            return "{" .. table.concat(items, ",") .. "}"
        end
    else
        error("unsupported JSON type: " .. t)
    end
end

local function call_bridge(action, payload)
    local request = {
        version = 1,
        action = action,
        payload = payload or {}
    }

    local json = encode_json(request)
    local cmd = "printf %s " .. shell_quote(json)
        .. " | VMOONGEN_BACKEND=vpp python3 "
        .. shell_quote(os.getenv("HOME") .. "/Projects/vMoonGen/tools/vpp_contract_bridge.py")

    local pipe = io.popen(cmd, "r")
    if not pipe then
        error("failed to start vpp contract bridge")
    end

    local output = pipe:read("*a")
    local ok = pipe:close()

    if ok == nil then
        error("bridge execution failed")
    end

    return output
end

function vpp.run_cli(socket_path, command)
    assert(socket_path, "socket_path required")
    assert(command, "command required")

    return call_bridge("run_cli", {
        socket_path = socket_path,
        command = command
    })
end

function vpp.show_version(socket_path)
    assert(socket_path, "socket_path required")
    return call_bridge("show_version", {
        socket_path = socket_path
    })
end

function vpp.show_interfaces(socket_path)
    assert(socket_path, "socket_path required")
    return call_bridge("show_interfaces", {
        socket_path = socket_path
    })
end

function vpp.show_plugins(socket_path)
    assert(socket_path, "socket_path required")
    return call_bridge("show_plugins", {
        socket_path = socket_path
    })
end

function vpp.show_sessions(socket_path)
    assert(socket_path, "socket_path required")
    return call_bridge("show_sessions", {
        socket_path = socket_path
    })
end

function vpp.set_interface_state(socket_path, interface, state)
    assert(socket_path, "socket_path required")
    assert(interface, "interface required")
    assert(state, "state required")

    return call_bridge("set_interface_state", {
        socket_path = socket_path,
        interface = interface,
        state = state
    })
end

return vpp
