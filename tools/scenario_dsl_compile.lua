#!/usr/bin/env luajit

local function script_dir()
  local src = (arg and arg[0]) or ""
  if type(src) ~= "string" or src == "" then
    return "."
  end
  src = src:gsub("\\", "/")
  return src:match("^(.*)/[^/]+$") or "."
end

local function setup_package_path()
  local dir = script_dir()
  local extra = table.concat({
    dir .. "/../lua/?.lua",
    dir .. "/../lua/?/init.lua",
    "./lua/?.lua",
    "./lua/?/init.lua",
  }, ";")
  package.path = extra .. ";" .. package.path
end

setup_package_path()

local dsl = require "scenario_dsl"
local planner = require "scenario_planner"

local function usage()
  io.stderr:write("Usage: tools/scenario_dsl_compile.lua <scenario.lua> [--ast|--plan|--scenario-v1|--worker-plan] [--workers N] [--shard-strategy contiguous|round_robin]\n")
end

local function json_escape(s)
  s = tostring(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  s = s:gsub("\b", "\\b")
  s = s:gsub("\f", "\\f")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return "\"" .. s .. "\""
end

local function is_array(tbl)
  return dsl.is_array(tbl)
end

local function json_encode(v)
  local tv = type(v)
  if tv == "nil" then
    return "null"
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "number" then
    return tostring(v)
  elseif tv == "string" then
    return json_escape(v)
  elseif tv ~= "table" then
    return json_escape(tostring(v))
  end

  if is_array(v) then
    local parts = {}
    for i = 1, #v do
      parts[#parts + 1] = json_encode(v[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = json_escape(k) .. ":" .. json_encode(v[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local file = arg[1]
local mode = "--plan"
local workers = 1
local shard_strategy = "contiguous"

local i = 2
while i <= #arg do
  local a = arg[i]
  if a == "--ast" or a == "--plan" or a == "--scenario-v1" or a == "--worker-plan" then
    mode = a
  elseif a == "--workers" then
    workers = tonumber(arg[i + 1]) or workers
    i = i + 1
  elseif a == "--shard-strategy" then
    shard_strategy = tostring(arg[i + 1] or shard_strategy)
    i = i + 1
  else
    usage()
    os.exit(2)
  end
  i = i + 1
end

if not file or (mode ~= "--plan" and mode ~= "--ast" and mode ~= "--scenario-v1" and mode ~= "--worker-plan") then
  usage()
  os.exit(2)
end

local scenario, parse_errors = dsl.parse_file(file)
if not scenario then
  io.stderr:write("[dsl] parse failed:\n")
  for _, e in ipairs(parse_errors or {}) do
    io.stderr:write(" - " .. tostring(e) .. "\n")
  end
  os.exit(1)
end

if mode == "--ast" then
  io.write(json_encode(scenario) .. "\n")
  os.exit(0)
end

local plan, compile_errors = dsl.compile(scenario)
if not plan then
  io.stderr:write("[dsl] compile failed:\n")
  for _, e in ipairs(compile_errors or {}) do
    io.stderr:write(" - " .. tostring(e) .. "\n")
  end
  os.exit(1)
end

if mode == "--scenario-v1" then
  local out, conv_errors = dsl.to_scenario_v1(scenario, plan)
  if not out then
    io.stderr:write("[dsl] scenario-v1 conversion failed:\n")
    for _, e in ipairs(conv_errors or {}) do
      io.stderr:write(" - " .. tostring(e) .. "\n")
    end
    os.exit(1)
  end
  io.write(json_encode(out) .. "\n")
  os.exit(0)
end

if mode == "--worker-plan" then
  local out, plan_errors = planner.build_worker_plan(plan, {
    workers = workers,
    shard_strategy = shard_strategy,
  })
  if not out then
    io.stderr:write("[dsl] worker-plan failed:\n")
    for _, e in ipairs(plan_errors or {}) do
      io.stderr:write(" - " .. tostring(e) .. "\n")
    end
    os.exit(1)
  end
  io.write(json_encode(out) .. "\n")
  os.exit(0)
end

io.write(json_encode(plan) .. "\n")
