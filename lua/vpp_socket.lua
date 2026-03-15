local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
typedef unsigned short sa_family_t;
typedef unsigned int socklen_t;
typedef long ssize_t;

struct sockaddr_un {
    sa_family_t sun_family;
    char sun_path[108];
};

int socket(int domain, int type, int protocol);
int connect(int sockfd, const struct sockaddr_un *addr, socklen_t addrlen);
ssize_t send(int sockfd, const void *buf, size_t len, int flags);
ssize_t recv(int sockfd, void *buf, size_t len, int flags);
int close(int fd);
char *strerror(int errnum);
int errno(void);
]]

local AF_UNIX = 1
local SOCK_STREAM = 1

local vpp = {}

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

local function last_error(prefix)
    local err = ffi.errno()
    local msg = ffi.string(ffi.C.strerror(err))
    error(prefix .. ": " .. msg)
end

local function connect_socket(path)
    local fd = ffi.C.socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 then
        last_error("socket")
    end

    local addr = ffi.new("struct sockaddr_un")
    addr.sun_family = AF_UNIX

    if #path >= 108 then
        ffi.C.close(fd)
        error("UNIX socket path too long: " .. path)
    end

    ffi.copy(addr.sun_path, path)
    local addrlen = ffi.sizeof(addr)

    if ffi.C.connect(fd, addr, addrlen) ~= 0 then
        local err = ffi.errno()
        ffi.C.close(fd)
        error("connect: " .. ffi.string(ffi.C.strerror(err)))
    end

    return fd
end

local function send_all(fd, data)
    local len = #data
    local sent = 0
    while sent < len do
        local n = ffi.C.send(fd, data:sub(sent + 1), len - sent, 0)
        if n < 0 then
            ffi.C.close(fd)
            last_error("send")
        end
        sent = sent + tonumber(n)
    end
end

local function recv_all(fd)
    local buf = ffi.new("char[4096]")
    local chunks = {}
    while true do
        local n = ffi.C.recv(fd, buf, 4096, 0)
        if n < 0 then
            ffi.C.close(fd)
            last_error("recv")
        end
        if n == 0 then
            break
        end
        chunks[#chunks + 1] = ffi.string(buf, tonumber(n))
    end
    ffi.C.close(fd)
    return table.concat(chunks)
end

function vpp.request(bridge_socket, action, payload)
    assert(bridge_socket, "bridge_socket required")
    assert(action, "action required")

    local request = {
        version = 1,
        action = action,
        payload = payload or {}
    }

    local fd = connect_socket(bridge_socket)
    send_all(fd, encode_json(request) .. "\n")
    return recv_all(fd)
end

function vpp.show_version(bridge_socket, vpp_socket)
    return vpp.request(bridge_socket, "show_version", {
        socket_path = vpp_socket
    })
end

function vpp.show_interfaces(bridge_socket, vpp_socket)
    return vpp.request(bridge_socket, "show_interfaces", {
        socket_path = vpp_socket
    })
end

function vpp.show_plugins(bridge_socket, vpp_socket)
    return vpp.request(bridge_socket, "show_plugins", {
        socket_path = vpp_socket
    })
end

function vpp.show_sessions(bridge_socket, vpp_socket)
    return vpp.request(bridge_socket, "show_sessions", {
        socket_path = vpp_socket
    })
end

function vpp.set_interface_state(bridge_socket, vpp_socket, interface, state)
    return vpp.request(bridge_socket, "set_interface_state", {
        socket_path = vpp_socket,
        interface = interface,
        state = state
    })
end

function vpp.run_cli(bridge_socket, vpp_socket, command)
    return vpp.request(bridge_socket, "run_cli", {
        socket_path = vpp_socket,
        command = command
    })
end

return vpp
