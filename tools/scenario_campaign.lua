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
  io.stderr:write("Usage: tools/scenario_campaign.lua <scenario.lua> [--workers N] [--step-s N] [--shard-strategy contiguous|round_robin] [--iterations N] [--lower-cps N] [--upper-cps N] [--campaign-id ID] [--objective NAME] [--out-dir DIR]\n")
end

local function to_number(v, default)
  local n = tonumber(v)
  if not n then
    return default
  end
  return n
end

local function parse_target(v)
  if type(v) == "number" then
    return v
  end
  if type(v) == "table" then
    if v.kind == "linear" then
      return v.to or v.from
    end
    if v.to then
      return v.to
    end
  end
  return nil
end

local function max_target_cps(plan)
  local maxv = 0
  for _, p in ipairs(plan.phases or {}) do
    local t = parse_target(p.target_cps)
    if type(t) == "number" and t > maxv then
      maxv = t
    end
  end
  return maxv
end

local function phase_target_from_candidate(phase_name, cps)
  if phase_name == "ramp" then
    return cps
  end
  if phase_name == "steady" then
    return cps
  end
  return nil
end

local function parse_args(args)
  local cfg = {
    scenario_file = nil,
    workers = 4,
    step_s = 1,
    shard_strategy = "contiguous",
    iterations = 8,
    lower_cps = nil,
    upper_cps = nil,
    campaign_id = "camp-" .. os.date("!%Y%m%d-%H%M%S"),
    objective = "max-tcp-cps-ipv4",
    out_dir = "",
  }

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--workers" then
      cfg.workers = to_number(args[i + 1], cfg.workers)
      i = i + 1
    elseif a == "--step-s" then
      cfg.step_s = to_number(args[i + 1], cfg.step_s)
      i = i + 1
    elseif a == "--shard-strategy" then
      cfg.shard_strategy = tostring(args[i + 1] or cfg.shard_strategy)
      i = i + 1
    elseif a == "--iterations" then
      cfg.iterations = to_number(args[i + 1], cfg.iterations)
      i = i + 1
    elseif a == "--lower-cps" then
      cfg.lower_cps = to_number(args[i + 1], cfg.lower_cps)
      i = i + 1
    elseif a == "--upper-cps" then
      cfg.upper_cps = to_number(args[i + 1], cfg.upper_cps)
      i = i + 1
    elseif a == "--campaign-id" then
      cfg.campaign_id = tostring(args[i + 1] or cfg.campaign_id)
      i = i + 1
    elseif a == "--objective" then
      cfg.objective = tostring(args[i + 1] or cfg.objective)
      i = i + 1
    elseif a == "--out-dir" then
      cfg.out_dir = tostring(args[i + 1] or cfg.out_dir)
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

  if not cfg.scenario_file then
    return nil, "Missing scenario file."
  end
  return cfg, nil
end

local function ensure_dir(path)
  if path and path ~= "" then
    os.execute("mkdir -p " .. string.format("%q", path))
  end
end

local function evaluate_run(run_summary, acceptance, workers)
  local m = run_summary.metrics or {}
  local max_drop = acceptance.max_drop_rate or 0.0
  local max_p95 = acceptance.max_latency_us_p95 or 1200.0
  local retry_setup = acceptance.max_tcp_retries_setup or 3
  local retry_budget = retry_setup * math.max(1, workers) * 100

  local drop_ok = (m.drop_rate or 1) <= max_drop
  local p95_ok = (m.latency_us_p95 or 1e12) <= max_p95
  local retry_ok = (m.tcp_retries_total or 1e12) <= retry_budget
  local pass = drop_ok and p95_ok and retry_ok

  local reasons = {}
  if not drop_ok then reasons[#reasons + 1] = "drop-rate above acceptance" end
  if not p95_ok then reasons[#reasons + 1] = "latency p95 above acceptance" end
  if not retry_ok then reasons[#reasons + 1] = "retry budget exceeded" end
  if #reasons == 0 then reasons[#reasons + 1] = "within acceptance envelope" end

  return pass, table.concat(reasons, "; ")
end

local cfg, arg_err = parse_args(arg)
if not cfg then
  usage()
  io.stderr:write(arg_err .. "\n")
  os.exit(2)
end

local scenario, parse_errors = dsl.parse_file(cfg.scenario_file)
if not scenario then
  io.stderr:write("[campaign] DSL parse failed:\n")
  for _, e in ipairs(parse_errors or {}) do
    io.stderr:write(" - " .. tostring(e) .. "\n")
  end
  os.exit(1)
end

local plan, compile_errors = dsl.compile(scenario)
if not plan then
  io.stderr:write("[campaign] DSL compile failed:\n")
  for _, e in ipairs(compile_errors or {}) do
    io.stderr:write(" - " .. tostring(e) .. "\n")
  end
  os.exit(1)
end

local base = max_target_cps(plan)
if base <= 0 then
  base = 100000
end

local lower = math.floor(cfg.lower_cps or (base * 0.5))
local upper = math.floor(cfg.upper_cps or (base * 1.5))
if lower < 1 then
  lower = 1
end
if upper < lower then
  upper = lower + 1
end

local acceptance = plan.acceptance or {
  max_drop_rate = 0.0,
  max_latency_us_p95 = 1200.0,
  max_tcp_retries_setup = 3,
}

if cfg.out_dir ~= "" then
  ensure_dir(cfg.out_dir)
  ensure_dir(cfg.out_dir .. "/runs")
end

local runs = {}
local best_value = nil
local best_run_id = nil
local lo = lower
local hi = upper

for iter = 1, cfg.iterations do
  if lo > hi then
    break
  end

  local candidate = math.floor((lo + hi) / 2)
  local run_id = string.format("%s-run-%03d", cfg.campaign_id, iter)

  local worker_plan, wp_errors = planner.build_worker_plan(plan, {
    workers = cfg.workers,
    shard_strategy = cfg.shard_strategy,
  })
  if not worker_plan then
    io.stderr:write("[campaign] worker-plan failed:\n")
    for _, e in ipairs(wp_errors or {}) do
      io.stderr:write(" - " .. tostring(e) .. "\n")
    end
    os.exit(1)
  end

  local artifacts = runtime.run(worker_plan, {
    step_s = cfg.step_s,
    target_cps_override = candidate,
    run_id = run_id,
    campaign_id = cfg.campaign_id,
  })
  local pass, note = evaluate_run(artifacts.run_summary, acceptance, cfg.workers)

  local verdict = pass and "pass" or "fail"
  runs[#runs + 1] = {
    run_id = run_id,
    candidate_value = candidate,
    candidate_unit = "cps",
    verdict = verdict,
    drop_rate = artifacts.run_summary.metrics.drop_rate,
    latency_us_p95 = artifacts.run_summary.metrics.latency_us_p95,
    notes = note,
  }

  if cfg.out_dir ~= "" then
    local run_dir = string.format("%s/runs/%03d-%d", cfg.out_dir, iter, candidate)
    ensure_dir(run_dir)
    json.dump_file(run_dir .. "/run-summary.json", artifacts.run_summary)
    json.dump_file(run_dir .. "/phase-summary.json", artifacts.phase_summary)
    json.dump_file(run_dir .. "/worker-metrics.json", artifacts.worker_metrics)
    json.dump_file(run_dir .. "/worker-plan.json", worker_plan)
  end

  if pass then
    best_value = candidate
    best_run_id = run_id
    lo = candidate + 1
  else
    hi = candidate - 1
  end
end

local recommended = nil
if lo <= hi then
  recommended = math.floor((lo + hi) / 2)
elseif best_value then
  recommended = best_value
end

local result = {
  schema_version = "1.0.0",
  campaign_id = cfg.campaign_id,
  objective = cfg.objective,
  search_method = "dichotomy",
  acceptance = {
    max_drop_rate = acceptance.max_drop_rate or 0.0,
    max_latency_us_p95 = acceptance.max_latency_us_p95 or 1200.0,
    max_tcp_retries_setup = acceptance.max_tcp_retries_setup or 3,
  },
  current_interval = {
    lower = lo,
    upper = hi,
    unit = "cps",
  },
  best_known = {
    run_id = best_run_id,
    value = best_value or 0,
    unit = "cps",
  },
  runs = runs,
  recommended_next = {
    candidate_value = recommended or 0,
    candidate_unit = "cps",
    reason = "dichotomy interval update",
  },
}

if cfg.out_dir ~= "" then
  json.dump_file(cfg.out_dir .. "/campaign-results.json", result)
end

io.write(json.encode(result))
io.write("\n")
