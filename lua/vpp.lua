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
    local cmd = "printf %s " .. shell_quote(json) .. " | python3 tools/vpp_contract_bridge.py"

    local pipe = io.popen(cmd, "r")
    if not pipe then
        error("failed to start contract bridge")
    end

    local output = pipe:read("*a")
    local ok, _, code = pipe:close()

    if not ok then
        error(string.format("bridge failed (code=%s): %s", tostring(code), output or ""))
    end

    print("[lua/vpp] bridge output: " .. output:gsub("%s+$", ""))
    return output
end

function vpp.connect(opts)
    opts = opts or {}
    return call_bridge("connect", {
        socket_path = opts.socket_path or "/run/vpp/api.sock"
    })
end

function vpp.disconnect()
    return call_bridge("disconnect", {})
end

function vpp.install_profile(profile)
    assert(profile, "profile required")
    return call_bridge("install_profile", profile)
end

function vpp.start_profile(name)
    assert(name, "profile name required")
    return call_bridge("start_profile", {
        name = name
    })
end

function vpp.stop_profile(name)
    assert(name, "profile name required")
    return call_bridge("stop_profile", {
        name = name
    })
end

function vpp.remove_profile(name)
    assert(name, "profile name required")
    return call_bridge("remove_profile", {
        name = name
    })
end

function vpp.get_profile_stats(name)
    assert(name, "profile name required")
    return call_bridge("get_profile_stats", {
        name = name
    })
end

function vpp.list_profiles()
    return call_bridge("list_profiles", {})
end

return vpp
