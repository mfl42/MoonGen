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

local function count_active_workers_by_role(workers)
  local counts = {
    client = 0,
    server = 0,
    ["real-server"] = 0,
  }
  for _, w in ipairs(workers or {}) do
    if w.active then
      local role = tostring(w.role or "client")
      if counts[role] == nil then
        counts[role] = 0
      end
      counts[role] = counts[role] + 1
    end
  end
  return counts
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
      cps_client_sum = 0,
      cps_server_sum = 0,
      cps_left_sum = 0,
      cps_right_sum = 0,
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
  local active_by_role = count_active_workers_by_role(workers)
  local arm_model = worker_plan.arm_model or {}
  local role_rate_policy = arm_model.role_rate_policy or {}
  local client_share = tonumber(role_rate_policy.client_cps_share)
  local server_share = tonumber(role_rate_policy.server_cps_share)
  if type(client_share) ~= "number" or type(server_share) ~= "number" then
    if worker_plan.mode == "2-arm" then
      local direction = tostring(arm_model.traffic_direction or "client_to_server")
      if direction == "full_duplex" then
        client_share = 0.5
        server_share = 0.5
      elseif direction == "server_to_client" then
        client_share = 0.0
        server_share = 1.0
      else
        client_share = 1.0
        server_share = 0.0
      end
    else
      client_share = 1.0
      server_share = 0.0
    end
  end
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
    cps_client_sum = 0,
    cps_server_sum = 0,
    cps_left_sum = 0,
    cps_right_sum = 0,
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
    local target_cps_client = target_cps
    local target_cps_server = 0
    if worker_plan.mode == "2-arm" then
      target_cps_client = target_cps * client_share
      target_cps_server = target_cps * server_share
    end
    local per_worker_target = target_cps / active_workers
    local per_client_target = (active_by_role.client > 0) and (target_cps_client / active_by_role.client) or 0
    local per_server_target = (active_by_role.server > 0) and (target_cps_server / active_by_role.server) or 0

    local tick_cps = 0
    local tick_cps_client = 0
    local tick_cps_server = 0
    local tick_cps_left = 0
    local tick_cps_right = 0
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

      local role = tostring(w.role or "client")
      local arm = tostring(w.arm or "left")
      local worker_cps = 0
      if w.active then
        if role == "server" then
          worker_cps = per_server_target
        elseif role == "client" then
          worker_cps = per_client_target
        else
          worker_cps = 0
        end
      end
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
      if role == "client" then
        tick_cps_client = tick_cps_client + worker_cps
      elseif role == "server" then
        tick_cps_server = tick_cps_server + worker_cps
      end
      if arm == "right" then
        tick_cps_right = tick_cps_right + worker_cps
      else
        tick_cps_left = tick_cps_left + worker_cps
      end
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
    totals.cps_client_sum = totals.cps_client_sum + tick_cps_client
    totals.cps_server_sum = totals.cps_server_sum + tick_cps_server
    totals.cps_left_sum = totals.cps_left_sum + tick_cps_left
    totals.cps_right_sum = totals.cps_right_sum + tick_cps_right
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
      pa.cps_client_sum = pa.cps_client_sum + tick_cps_client
      pa.cps_server_sum = pa.cps_server_sum + tick_cps_server
      pa.cps_left_sum = pa.cps_left_sum + tick_cps_left
      pa.cps_right_sum = pa.cps_right_sum + tick_cps_right
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
  local mean_cps_client = totals.samples > 0 and (totals.cps_client_sum / totals.samples) or 0
  local mean_cps_server = totals.samples > 0 and (totals.cps_server_sum / totals.samples) or 0
  local mean_cps_left = totals.samples > 0 and (totals.cps_left_sum / totals.samples) or 0
  local mean_cps_right = totals.samples > 0 and (totals.cps_right_sum / totals.samples) or 0
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
      cps_client = mean_cps_client,
      cps_server = mean_cps_server,
      cps_left_arm = mean_cps_left,
      cps_right_arm = mean_cps_right,
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
        cps_client = n > 0 and (pa.cps_client_sum / n) or 0,
        cps_server = n > 0 and (pa.cps_server_sum / n) or 0,
        cps_left_arm = n > 0 and (pa.cps_left_sum / n) or 0,
        cps_right_arm = n > 0 and (pa.cps_right_sum / n) or 0,
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
  local arm_summary = {}
  local role_summary = {}
  if opts.campaign_id then
    worker_metrics.campaign_id = tostring(opts.campaign_id)
  end
  for _, w in ipairs(workers) do
    local ws = worker_stats[w.worker_id]
    local n = ws.active_samples > 0 and ws.active_samples or 1
    local avg_cps = ws.cps_sum / n
    local avg_drop_rate = ws.drop_sum / n
    local role = tostring(w.role or "client")
    local arm = tostring(w.arm or "left")

    table.insert(worker_metrics.workers, {
      worker_id = ws.worker_id,
      queue_id = ws.queue_id,
      avg_cps = avg_cps,
      peak_active_sessions = round(ws.peak_active_sessions),
      avg_drop_rate = avg_drop_rate,
      latency_us_p95_max = ws.latency_p95_max,
      retries_total = ws.retries_total,
      shard = w.shard,
      role = role,
      arm = arm,
    })

    local a = arm_summary[arm] or {
      workers = 0,
      avg_cps_sum = 0,
      avg_drop_sum = 0,
      latency_us_p95_max = 0,
      retries_total = 0,
      peak_active_sessions = 0,
    }
    a.workers = a.workers + 1
    a.avg_cps_sum = a.avg_cps_sum + avg_cps
    a.avg_drop_sum = a.avg_drop_sum + avg_drop_rate
    if ws.latency_p95_max > a.latency_us_p95_max then
      a.latency_us_p95_max = ws.latency_p95_max
    end
    a.retries_total = a.retries_total + ws.retries_total
    a.peak_active_sessions = a.peak_active_sessions + round(ws.peak_active_sessions)
    arm_summary[arm] = a

    local rsum = role_summary[role] or {
      workers = 0,
      avg_cps_sum = 0,
      avg_drop_sum = 0,
      latency_us_p95_max = 0,
      retries_total = 0,
      peak_active_sessions = 0,
    }
    rsum.workers = rsum.workers + 1
    rsum.avg_cps_sum = rsum.avg_cps_sum + avg_cps
    rsum.avg_drop_sum = rsum.avg_drop_sum + avg_drop_rate
    if ws.latency_p95_max > rsum.latency_us_p95_max then
      rsum.latency_us_p95_max = ws.latency_p95_max
    end
    rsum.retries_total = rsum.retries_total + ws.retries_total
    rsum.peak_active_sessions = rsum.peak_active_sessions + round(ws.peak_active_sessions)
    role_summary[role] = rsum
  end

  local function finalize_summary(input)
    local out = {}
    for k, v in pairs(input) do
      local n = v.workers > 0 and v.workers or 1
      out[k] = {
        workers = v.workers,
        avg_cps = v.avg_cps_sum / n,
        avg_drop_rate = v.avg_drop_sum / n,
        latency_us_p95_max = v.latency_us_p95_max,
        retries_total = v.retries_total,
        peak_active_sessions = v.peak_active_sessions,
      }
    end
    return out
  end
  worker_metrics.arm_summary = finalize_summary(arm_summary)
  worker_metrics.role_summary = finalize_summary(role_summary)

  return {
    run_summary = run_summary,
    phase_summary = phase_summary,
    worker_metrics = worker_metrics,
  }
end

return M
