local M = {}

local function copy_table(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    out[k] = v
  end
  return out
end

local function shallow_array(tbl)
  local out = {}
  for i, v in ipairs(tbl or {}) do
    out[i] = v
  end
  return out
end

local function clamp_int(v, default)
  if type(v) ~= "number" then
    return default
  end
  if v < 0 then
    return default
  end
  return math.floor(v + 0.5)
end

local function resolve_number(v, default)
  if type(v) == "number" then
    return v
  end
  if type(v) == "table" then
    if v.__expr == "dist_fixed" and type(v.value) == "number" then
      return v.value
    end
    if v.__expr == "dist_uniform" and type(v.min) == "number" and type(v.max) == "number" then
      return (v.min + v.max) / 2
    end
  end
  return default
end

local function build_contiguous_ranges(total, workers)
  local out = {}
  local cursor = 1
  local base = math.floor(total / workers)
  local rem = total % workers

  for i = 1, workers do
    local count = base + ((i <= rem) and 1 or 0)
    local start_id = cursor
    local end_id = cursor + count - 1
    if count <= 0 then
      start_id = 0
      end_id = -1
    end
    out[i] = {
      start_id = start_id,
      end_id = end_id,
      count = count,
    }
    cursor = end_id + 1
  end
  return out
end

local function build_round_robin_buckets(total, workers)
  local buckets = {}
  for i = 1, workers do
    buckets[i] = { count = 0, first_id = nil, last_id = nil }
  end
  for id = 1, total do
    local wid = ((id - 1) % workers) + 1
    local b = buckets[wid]
    b.count = b.count + 1
    if not b.first_id then
      b.first_id = id
    end
    b.last_id = id
  end
  for i = 1, workers do
    local b = buckets[i]
    buckets[i] = {
      start_id = b.first_id or 0,
      end_id = b.last_id or -1,
      count = b.count,
      assignment = "round_robin",
    }
  end
  return buckets
end

local function parse_target(target)
  if type(target) == "number" then
    return target
  end
  if type(target) == "table" then
    if target.kind == "linear" then
      return target.to or target.from
    end
    if target.to then
      return target.to
    end
    if target.from then
      return target.from
    end
  end
  return nil
end

local function build_phase_targets(phases)
  local max_cps = 0
  for _, phase in ipairs(phases or {}) do
    local cps = parse_target(phase.target_cps)
    if type(cps) == "number" and cps > max_cps then
      max_cps = cps
    end
  end
  return max_cps
end

local function derive_arm_model(plan)
  local mode = plan.mode or "2-arm"
  local arm_model = plan.arm_model or {}
  local arms = arm_model.arms or {}
  local role_rate_policy = arm_model.role_rate_policy or {}
  local left = arms.left or {}
  local right = arms.right or {}

  local left_role = left.role or "client"
  local right_role = right.role or ((mode == "1-arm") and "real-server" or "server")
  local direction = arm_model.traffic_direction or "client_to_server"
  local traversal = arm_model.traversal or "cross-arm"
  local client_cps_share = role_rate_policy.client_cps_share
  local server_cps_share = role_rate_policy.server_cps_share

  if type(client_cps_share) ~= "number" or type(server_cps_share) ~= "number" then
    if mode == "2-arm" then
      if direction == "full_duplex" then
        client_cps_share = 0.5
        server_cps_share = 0.5
      elseif direction == "server_to_client" then
        client_cps_share = 0.0
        server_cps_share = 1.0
      else
        client_cps_share = 1.0
        server_cps_share = 0.0
      end
    else
      client_cps_share = 1.0
      server_cps_share = 0.0
    end
  end

  return {
    traversal = traversal,
    traffic_direction = direction,
    role_rate_policy = {
      client_cps_share = client_cps_share,
      server_cps_share = server_cps_share,
    },
    left = {
      role = left_role,
      port_index = (type(left.port_index) == "number") and left.port_index or 0,
    },
    right = {
      role = right_role,
      port_index = (type(right.port_index) == "number") and right.port_index or 1,
    },
  }
end

function M.build_worker_plan(plan, opts)
  if type(plan) ~= "table" then
    return nil, { "Plan object is missing." }
  end
  opts = opts or {}

  local workers = clamp_int(opts.workers, 1)
  if workers < 1 then
    workers = 1
  end

  local populations = plan.populations or {}
  local cpe_count = clamp_int(resolve_number(populations.cpe_count, 1), 1)
  if cpe_count < 1 then
    cpe_count = 1
  end

  local ue_per_cpe = clamp_int(resolve_number(populations.ue_per_cpe, 1), 1)
  if ue_per_cpe < 1 then
    ue_per_cpe = 1
  end

  local ue_count = clamp_int(resolve_number(populations.ue_count, cpe_count * ue_per_cpe), cpe_count * ue_per_cpe)
  if ue_count < 1 then
    ue_count = cpe_count * ue_per_cpe
  end

  local shard_dimension = "cpe"
  local placement = plan.placement or {}
  if placement.shard_by == "ue" then
    shard_dimension = "ue"
  end
  local total_shards = (shard_dimension == "ue") and ue_count or cpe_count

  local strategy = opts.shard_strategy
  if strategy ~= "round_robin" then
    strategy = "contiguous"
  end

  local ranges
  if strategy == "round_robin" then
    ranges = build_round_robin_buckets(total_shards, workers)
  else
    ranges = build_contiguous_ranges(total_shards, workers)
  end

  local max_cps = build_phase_targets(plan.phases)
  local arm_model = derive_arm_model(plan)
  local default_parallel_sessions = clamp_int(opts.parallel_sessions, 2)
  if default_parallel_sessions < 1 then
    default_parallel_sessions = 1
  end
  local estimated_microflows = ue_count * default_parallel_sessions

  local worker_items = {}
  local left_workers = (plan.mode == "1-arm") and workers or math.floor((workers + 1) / 2)
  for i = 1, workers do
    local r = ranges[i]
    local role = "client"
    local arm = "left"
    if plan.mode == "2-arm" then
      if i <= left_workers then
        role = tostring(arm_model.left.role or "client")
        arm = "left"
      else
        role = tostring(arm_model.right.role or "server")
        arm = "right"
      end
    end
    local w = {
      worker_id = i,
      queue_id = i - 1,
      shard = {
        dimension = shard_dimension,
        strategy = strategy,
        start_id = r.start_id,
        end_id = r.end_id,
        count = r.count,
      },
      role = (plan.mode == "1-arm") and "client" or "dual",
      arm = arm,
      active = r.count > 0,
      estimated = {
        cps_target = max_cps > 0 and (max_cps / workers) or 0,
        microflows = estimated_microflows > 0 and math.floor(estimated_microflows / workers) or 0,
      },
    }
    w.role = role
    if strategy == "round_robin" then
      w.shard.assignment = "round_robin"
    end
    worker_items[i] = w
  end

  local out = {
    schema_version = "1.0.0",
    plan_type = "worker-plan",
    scenario_id = plan.scenario_id,
    mode = plan.mode,
    engine = plan.engine,
    fidelity = plan.fidelity,
    graph = copy_table(plan.graph or {}),
    placement = copy_table(plan.placement or {}),
    addressing = copy_table(plan.addressing or {}),
    arm_model = copy_table(arm_model),
    observability = copy_table(plan.observability or {}),
    phases = shallow_array(plan.phases or {}),
    totals = {
      workers = workers,
      shard_dimension = shard_dimension,
      total_shards = total_shards,
      cpe_count = cpe_count,
      ue_per_cpe = ue_per_cpe,
      ue_count = ue_count,
      estimated_microflows = estimated_microflows,
      target_cps = max_cps,
    },
    workers = worker_items,
  }

  return out, nil
end

return M
