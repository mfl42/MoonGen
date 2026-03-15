local mg      = require "moongen"
local memory  = require "memory"
local device  = require "device"
local timer   = require "timer"

package.path = package.path .. ";./lua/?.lua"
local vpp = require "vpp_socket"

local BRIDGE_SOCKET = "/tmp/vmoongen.sock"
local VPP_SOCKET    = "/home/mfl42/Projects/vpp/run/cli.sock"

function configure(parser)
    parser:description("Multi-threaded MoonGen load generator with a dedicated high-speed VPP control task")
    parser:argument("txDev", "Device to transmit from."):convert(tonumber)
    parser:option("-q --queues", "Number of TX worker threads."):default(2):convert(tonumber)
    parser:option("-s --size", "Packet size in bytes."):default(60):convert(tonumber)
    parser:option("-r --rate", "Rate in Mbit/s per queue (best effort)."):default(1000):convert(tonumber)
    parser:option("--dst-mac", "Destination MAC address."):default("90:e2:ba:8f:00:01")
    parser:option("--dst-ip", "Destination IPv4 address."):default("198.18.0.1")
    parser:option("--control-ms", "Control-plane polling interval in milliseconds."):default(1000):convert(tonumber)
end

function master(args)
    local dev = device.config({
        port = args.txDev,
        txQueues = args.queues,
        rxQueues = 1
    })

    device.waitForLinks()

    for i = 0, args.queues - 1 do
        local txq = dev:getTxQueue(i)
        mg.startTask("loadSlave", txq, args.size, args.rate, args.dstMac, args.dstIp)
    end

    mg.startTask("controlSlave", args.control_ms)
    mg.waitForTasks()
end

function loadSlave(queue, size, rate, dstMac, dstIp)
    local mem = memory.createMemPool(function(buf)
        local pkt = buf:getUdpPacket()
        pkt:fill({
            ethDst = dstMac,
            ethSrc = queue,
            ip4Dst = dstIp,
            ip4Src = "198.18.0.2",
            udpSrc = 1234,
            udpDst = 5678,
            pktLength = size
        })
    end)

    local bufs = mem:bufArray(1024)

    if queue.setRate then
        queue:setRate(rate)
    end

    while mg.running() do
        bufs:alloc(size)
        queue:send(bufs)
    end
end

function controlSlave(intervalMs)
    local poll = timer:new(intervalMs / 1000)

    while mg.running() do
        if poll:expired() then
            print(vpp.show_sessions(BRIDGE_SOCKET, VPP_SOCKET))
            poll:reset()
        end
        mg.sleepMillisIdle(10)
    end
end
