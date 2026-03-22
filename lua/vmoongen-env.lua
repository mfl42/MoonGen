local mod = {}

local function env(name, default)
    local value = os.getenv(name)
    if value == nil or value == "" then
        return default
    end
    return value
end

function mod.root()
    return env("VMOONGEN_ROOT", ".")
end

function mod.bridge_socket()
    return env("VMOONGEN_BRIDGE_SOCKET", "/tmp/vmoongen.sock")
end

function mod.vpp_root()
    local home = env("HOME", "")
    local configured = env("VPP_ROOT", env("VMOONGEN_VPP_ROOT", ""))
    if configured ~= "" then
        return configured
    end

    local root = mod.root()
    local candidates = {
        root .. "/../vpp",
        home .. "/Projects/vpp",
        home .. "/vpp",
    }

    local function exists(path)
        local ok, _, code = os.rename(path, path)
        return ok or code == 13
    end

    for _, candidate in ipairs(candidates) do
        if exists(candidate) then
            return candidate
        end
    end

    return home .. "/Projects/vpp"
end

function mod.vpp_socket()
    return env("VPP_SOCKET", mod.vpp_root() .. "/run/cli.sock")
end

return mod
