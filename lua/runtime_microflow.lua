local M = {}

local function clamp(v, lo, hi)
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

local function now_rfc3339_utc(offset_s)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() + (offset_s or 0))
end

local function round(x)
  if x >= 0 then
    return math.floor(x + 0.5)
  end
  return math.ceil(x - 0.5)
end

local function phase_target_cps(phase, now_s, target_cps_override)
  if type(target_cps_override) == "number" and (phase.name == "ramp" or phase.name == "steady") then
    if phase.name == "ramp" then
      local duration = phase.duration_s
      if duration <= 0 then
        return target_cps_override
      end
      local local_t = clamp((now_s - phase.offset_s) / duration, 0, 1)
      return target_cps_override * local_t
    end
    return target_cps_override
  end

  local t = phase.target_cps
  if type(t) == "number" then
    return t
  end
  if type(t) == "table" and t.kind == "linear" then
    local duration = phase.duration_s
    if duration <= 0 then
      return t.to or t.from or 0
    end
    local local_t = clamp((now_s - phase.offset_s) / duration, 0, 1)
    local from = t.from or 0
    local to = t.to or from
    return from + (to - from) * local_t
  end
  return 0
end

local function active_phase(phases, now_s)
  local current = nil
  for _, p in ipairs(phases or {}) do
    local start_s = p.offset_s or 0
    local end_s = start_s + (p.duration_s or 0)
    if now_s >= start_s and now_s < end_s then
      current = p
      break
    end
    if p.duration_s == 0 and now_s >= start_s then
      current = p
    end
  end
  return current
end

local function count_active_workers(workers)
  local n = 0
  for _, w in ipairs(workers or {}) do
    if w.active then
      n = n + 1
    end
  end
  if n < 1 then
    n = 1
  end
  return n
end

local function new_phase_accumulator(phases)
  local out = {}
  for _, p in ipairs(phases or {}) do
    out[p.name] = {
      samples = 0,
      cps_sum = 0,
      throughput_sum = 0,
      drop_sum = 0,
      latency_p95_sum = 0,
      retries_sum = 0,
    }
  end
  return out
end

function M.run(worker_plan, opts)
  opts = opts or {}
  local step_s = tonumber(opts.step_s) or 1
  if step_s <= 0 then
    step_s = 1
  end
  local target_cps_override = tonumber(opts.target_cps_override)

  local phases = worker_plan.phases or {}
  local workers = worker_plan.workers or {}
  local active_workers = count_active_workers(workers)
  local total_duration_s = 0
  for _, p in ipairs(phases) do
    local end_s = (p.offset_s or 0) + (p.duration_s or 0)
    if end_s > total_duration_s then
      total_duration_s = end_s
    end
  end

  local run_id = opts.run_id or ("sim-" .. os.date("!%Y%m%d-%H%M%S"))
  local phase_acc = new_phase_accumulator(phases)
  local worker_stats = {}
  for _, w in ipairs(workers) do
    worker_stats[w.worker_id] = {
      worker_id = w.worker_id,
      queue_id = w.queue_id,
      active_samples = 0,
      cps_sum = 0,
      peak_active_sessions = 0,
      drop_sum = 0,
      latency_p95_max = 0,
      retries_total = 0,
      active_sessions = 0,
    }
  end

  local totals = {
    cps_sum = 0,
    throughput_sum = 0,
    drop_sum = 0,
    latency_p95_sum = 0,
    retries_total = 0,
    concurrent_peak = 0,
    samples = 0,
  }

  local t = 0
  while t <= total_duration_s do
    local phase = active_phase(phases, t)
    local phase_name = phase and phase.name or "steady"
    local target_cps = phase and phase_target_cps(phase, t, target_cps_override) or 0
    local per_worker_target = target_cps / active_workers

    local tick_cps = 0
    local tick_throughput = 0
    local tick_drop = 0
    local tick_latency = 0
    local tick_concurrent = 0
    local tick_retries = 0

    for _, w in ipairs(workers) do
      local ws = worker_stats[w.worker_id]
      local capacity = (w.estimated and w.estimated.cps_target) or per_worker_target
      if capacity <= 0 then
        capacity = per_worker_target > 0 and per_worker_target or 1
      end

      local worker_cps = w.active and per_worker_target or 0
      local load = worker_cps / capacity
      local drop_rate = clamp((load - 1.0) * 0.03, 0, 1)
      local latency_p95 = 250 + (clamp(load, 0, 2.5) * 500)

      local opens = worker_cps * step_s
      local closes
      if phase_name == "start" then
        closes = opens * 0.05
      elseif phase_name == "ramp" then
        closes = opens * 0.10
      elseif phase_name == "steady" then
        closes = opens * 0.20
      elseif phase_name == "finish" then
        closes = ws.active_sessions * 0.35 + opens
      else
        closes = ws.active_sessions + opens
      end

      ws.active_sessions = math.max(0, ws.active_sessions + opens - closes)
      local retries = round(opens * drop_rate * 0.10)
      local throughput_bps = worker_cps * 1200 * 8 * (1 - drop_rate)

      ws.active_samples = ws.active_samples + 1
      ws.cps_sum = ws.cps_sum + worker_cps
      ws.drop_sum = ws.drop_sum + drop_rate
      if ws.active_sessions > ws.peak_active_sessions then
        ws.peak_active_sessions = ws.active_sessions
      end
      if latency_p95 > ws.latency_p95_max then
        ws.latency_p95_max = latency_p95
      end
      ws.retries_total = ws.retries_total + retries

      tick_cps = tick_cps + worker_cps
      tick_throughput = tick_throughput + throughput_bps
      tick_drop = tick_drop + drop_rate
      tick_latency = tick_latency + latency_p95
      tick_concurrent = tick_concurrent + ws.active_sessions
      tick_retries = tick_retries + retries
    end

    local avg_drop = tick_drop / active_workers
    local avg_latency_p95 = tick_latency / active_workers
    totals.samples = totals.samples + 1
    totals.cps_sum = totals.cps_sum + tick_cps
    totals.throughput_sum = totals.throughput_sum + tick_throughput
    totals.drop_sum = totals.drop_sum + avg_drop
    totals.latency_p95_sum = totals.latency_p95_sum + avg_latency_p95
    totals.retries_total = totals.retries_total + tick_retries
    if tick_concurrent > totals.concurrent_peak then
      totals.concurrent_peak = tick_concurrent
    end

    local pa = phase_acc[phase_name]
    if pa then
      pa.samples = pa.samples + 1
      pa.cps_sum = pa.cps_sum + tick_cps
      pa.throughput_sum = pa.throughput_sum + tick_throughput
      pa.drop_sum = pa.drop_sum + avg_drop
      pa.latency_p95_sum = pa.latency_p95_sum + avg_latency_p95
      pa.retries_sum = pa.retries_sum + tick_retries
    end

    t = t + step_s
  end

  local started_at = now_rfc3339_utc(0)
  local finished_at = now_rfc3339_utc(total_duration_s)

  local mean_cps = totals.samples > 0 and (totals.cps_sum / totals.samples) or 0
  local mean_throughput = totals.samples > 0 and (totals.throughput_sum / totals.samples) or 0
  local mean_drop = totals.samples > 0 and (totals.drop_sum / totals.samples) or 0
  local mean_p95 = totals.samples > 0 and (totals.latency_p95_sum / totals.samples) or 0
  local p50 = math.max(0, mean_p95 * 0.6)
  local p99 = mean_p95 * 1.2

  local run_summary = {
    schema_version = "1.0.0",
    run_id = run_id,
    scenario_id = worker_plan.scenario_id,
    mode = worker_plan.mode,
    transport = worker_plan.engine == "vpp" and "tcp-vpp" or "tcp-lite",
    started_at = started_at,
    finished_at = finished_at,
    verdict = (mean_drop <= 0.0001) and "pass" or "inconclusive",
    stop_reason = "simulation-complete",
    metrics = {
      throughput_bps = mean_throughput,
      cps = mean_cps,
      concurrent_sessions = round(totals.concurrent_peak),
      drop_rate = mean_drop,
      latency_us_p50 = p50,
      latency_us_p95 = mean_p95,
      latency_us_p99 = p99,
      tcp_retries_total = totals.retries_total,
    },
  }
  if opts.campaign_id then
    run_summary.campaign_id = tostring(opts.campaign_id)
  end

  local phase_summary = {
    schema_version = "1.0.0",
    run_id = run_id,
    scenario_id = worker_plan.scenario_id,
    phases = {},
  }
  if opts.campaign_id then
    phase_summary.campaign_id = tostring(opts.campaign_id)
  end
  for _, p in ipairs(phases) do
    local pa = phase_acc[p.name] or {}
    local n = pa.samples or 0
    local item = {
      name = p.name,
      started_at = now_rfc3339_utc(p.offset_s or 0),
      finished_at = now_rfc3339_utc((p.offset_s or 0) + (p.duration_s or 0)),
      duration_s = p.duration_s or 0,
      target = {
        cps = phase_target_cps(p, (p.offset_s or 0) + (p.duration_s or 0), target_cps_override),
      },
      observed = {
        cps = n > 0 and (pa.cps_sum / n) or 0,
        throughput_bps = n > 0 and (pa.throughput_sum / n) or 0,
        drop_rate = n > 0 and (pa.drop_sum / n) or 0,
        latency_us_p95 = n > 0 and (pa.latency_p95_sum / n) or 0,
        tcp_retries = pa.retries_sum or 0,
      },
      verdict = (n > 0 and (pa.drop_sum / n) <= 0.0001) and "pass" or "inconclusive",
    }
    table.insert(phase_summary.phases, item)
  end

  local worker_metrics = {
    schema_version = "1.0.0",
    run_id = run_id,
    scenario_id = worker_plan.scenario_id,
    workers = {},
  }
  if opts.campaign_id then
    worker_metrics.campaign_id = tostring(opts.campaign_id)
  end
  for _, w in ipairs(workers) do
    local ws = worker_stats[w.worker_id]
    local n = ws.active_samples > 0 and ws.active_samples or 1
    table.insert(worker_metrics.workers, {
      worker_id = ws.worker_id,
      queue_id = ws.queue_id,
      avg_cps = ws.cps_sum / n,
      peak_active_sessions = round(ws.peak_active_sessions),
      avg_drop_rate = ws.drop_sum / n,
      latency_us_p95_max = ws.latency_p95_max,
      retries_total = ws.retries_total,
      shard = w.shard,
      role = w.role,
    })
  end

  return {
    run_summary = run_summary,
    phase_summary = phase_summary,
    worker_metrics = worker_metrics,
  }
end

return M
