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
local runtime = require "runtime_microflow"
local json = require "jsonlite"

local function usage()
  io.stderr:write("Usage:\n")
  io.stderr:write("  tools/scenario_runtime_skeleton.lua <scenario.lua> [--workers N] [--step-s N] [--shard-strategy contiguous|round_robin] [--target-cps-override N] [--run-id ID] [--campaign-id ID] [--out-dir DIR]\n")
  io.stderr:write("  tools/scenario_runtime_skeleton.lua --worker-plan-file <worker-plan.json> [--step-s N] [--target-cps-override N] [--run-id ID] [--campaign-id ID] [--out-dir DIR]\n")
end

local function parse_args(args)
  local cfg = {
    scenario_file = nil,
    worker_plan_file = nil,
    workers = 4,
    step_s = 1,
    shard_strategy = "contiguous",
    out_dir = nil,
    run_id = nil,
    campaign_id = nil,
    target_cps_override = nil,
  }

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--worker-plan-file" then
      cfg.worker_plan_file = tostring(args[i + 1] or "")
      i = i + 1
    elseif a == "--workers" then
      cfg.workers = tonumber(args[i + 1]) or cfg.workers
      i = i + 1
    elseif a == "--step-s" then
      cfg.step_s = tonumber(args[i + 1]) or cfg.step_s
      i = i + 1
    elseif a == "--shard-strategy" then
      cfg.shard_strategy = tostring(args[i + 1] or cfg.shard_strategy)
      i = i + 1
    elseif a == "--out-dir" then
      cfg.out_dir = tostring(args[i + 1] or "")
      i = i + 1
    elseif a == "--run-id" then
      cfg.run_id = tostring(args[i + 1] or "")
      i = i + 1
    elseif a == "--campaign-id" then
      cfg.campaign_id = tostring(args[i + 1] or "")
      i = i + 1
    elseif a == "--target-cps-override" then
      cfg.target_cps_override = tonumber(args[i + 1]) or cfg.target_cps_override
      i = i + 1
    elseif type(a) == "string" and a:sub(1, 2) == "--" then
      return nil, "Unknown argument: " .. tostring(a)
    elseif not cfg.scenario_file then
      cfg.scenario_file = a
    else
      return nil, "Unexpected positional argument: " .. tostring(a)
    end
    i = i + 1
  end

  if cfg.worker_plan_file == "" then
    return nil, "Missing value for --worker-plan-file."
  end
  if cfg.worker_plan_file and cfg.scenario_file then
    return nil, "Use either scenario file or --worker-plan-file, not both."
  end
  if not cfg.worker_plan_file and not cfg.scenario_file then
    return nil, "Missing scenario file (or use --worker-plan-file)."
  end

  return cfg, nil
end

local cfg, arg_err = parse_args(arg)
if not cfg then
  usage()
  io.stderr:write(arg_err .. "\n")
  os.exit(2)
end

local worker_plan = nil
if cfg.worker_plan_file then
  local loaded, load_err = json.load_file(cfg.worker_plan_file)
  if not loaded then
    io.stderr:write("[runtime] worker-plan load failed: " .. tostring(load_err) .. "\n")
    os.exit(1)
  end
  worker_plan = loaded
else
  local scenario, parse_errors = dsl.parse_file(cfg.scenario_file)
  if not scenario then
    io.stderr:write("[runtime] DSL parse failed:\n")
    for _, e in ipairs(parse_errors or {}) do
      io.stderr:write(" - " .. tostring(e) .. "\n")
    end
    os.exit(1)
  end

  local plan, compile_errors = dsl.compile(scenario)
  if not plan then
    io.stderr:write("[runtime] DSL compile failed:\n")
    for _, e in ipairs(compile_errors or {}) do
      io.stderr:write(" - " .. tostring(e) .. "\n")
    end
    os.exit(1)
  end

  local wp, wp_errors = planner.build_worker_plan(plan, {
    workers = cfg.workers,
    shard_strategy = cfg.shard_strategy,
  })
  if not wp then
    io.stderr:write("[runtime] worker-plan failed:\n")
    for _, e in ipairs(wp_errors or {}) do
      io.stderr:write(" - " .. tostring(e) .. "\n")
    end
    os.exit(1)
  end
  worker_plan = wp
end

local artifacts = runtime.run(worker_plan, {
  step_s = cfg.step_s,
  target_cps_override = cfg.target_cps_override,
  run_id = cfg.run_id,
  campaign_id = cfg.campaign_id,
})

if cfg.out_dir and cfg.out_dir ~= "" then
  os.execute("mkdir -p " .. string.format("%q", cfg.out_dir))
  local ok1, err1 = json.dump_file(cfg.out_dir .. "/run-summary.json", artifacts.run_summary)
  local ok2, err2 = json.dump_file(cfg.out_dir .. "/phase-summary.json", artifacts.phase_summary)
  local ok3, err3 = json.dump_file(cfg.out_dir .. "/worker-metrics.json", artifacts.worker_metrics)
  if not ok1 or not ok2 or not ok3 then
    io.stderr:write("[runtime] artifact write failed:\n")
    if err1 then io.stderr:write(" - run-summary: " .. tostring(err1) .. "\n") end
    if err2 then io.stderr:write(" - phase-summary: " .. tostring(err2) .. "\n") end
    if err3 then io.stderr:write(" - worker-metrics: " .. tostring(err3) .. "\n") end
    os.exit(1)
  end
end

io.write(json.encode({
  worker_plan = worker_plan,
  run_summary = artifacts.run_summary,
  phase_summary = artifacts.phase_summary,
  worker_metrics = artifacts.worker_metrics,
}))
io.write("\n")
