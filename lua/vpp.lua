---

## 3. Replace the Lua API with a profile-driven one

Replace `lua/vpp.lua` with this:

```lua
local vpp = {}

local function shell_quote(s)
    s = tostring(s or "")
    s = s:gsub("'", "'\"'\"'")
    return "'" .. s .. "'"
end

local function run_command(cmd)
    local pipe = io.popen(cmd, "r")
    if not pipe then
        error("failed to run command: " .. cmd)
    end

    local output = pipe:read("*a")
    local ok, _, code = pipe:close()

    if not ok then
        error(string.format("command failed (code=%s): %s\n%s", tostring(code), cmd, output or ""))
    end

    return output
end

local function bridge(args)
    local cmd = "python3 tools/vpp_mock_bridge.py"
    for _, arg in ipairs(args) do
        cmd = cmd .. " " .. shell_quote(arg)
    end
    local output = run_command(cmd)
    print("[lua/vpp] bridge output: " .. output:gsub("%s+$", ""))
    return output
end

local function require_field(tbl, key)
    if tbl[key] == nil then
        error("missing required field: " .. key)
    end
end

local function encode_servers(servers)
    local parts = {}
    for _, s in ipairs(servers or {}) do
        local ip = s.ip or "0.0.0.0"
        local port = tonumber(s.port or 0)
        parts[#parts + 1] = string.format("%s:%d", ip, port)
    end
    return table.concat(parts, ",")
end

function vpp.connect(opts)
    opts = opts or {}
    return bridge({
        "connect",
        opts.socket_path or "/run/vpp/api.sock"
    })
end

function vpp.disconnect()
    return bridge({ "disconnect" })
end

function vpp.install_profile(profile)
    assert(profile, "profile required")
    require_field(profile, "name")
    require_field(profile, "protocol")
    require_field(profile, "clients")
    require_field(profile, "servers")
    require_field(profile, "cps")
    require_field(profile, "duration_s")

    return bridge({
        "install_profile",
        profile.name,
        profile.protocol,
        profile.clients,
        encode_servers(profile.servers),
        tostring(profile.cps),
        tostring(profile.duration_s),
        profile.payload or "",
        profile.close_mode or "graceful",
        tostring(profile.stats_interval_ms or 1000)
    })
end

function vpp.start_profile(name)
    assert(name, "profile name required")
    return bridge({ "start_profile", name })
end

function vpp.stop_profile(name)
    assert(name, "profile name required")
    return bridge({ "stop_profile", name })
end

function vpp.remove_profile(name)
    assert(name, "profile name required")
    return bridge({ "remove_profile", name })
end

function vpp.get_profile_stats(name)
    assert(name, "profile name required")
    return bridge({ "get_profile_stats", name })
end

function vpp.list_profiles()
    return bridge({ "list_profiles" })
end

return vpp
