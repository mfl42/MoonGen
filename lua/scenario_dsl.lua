local M = {}

local function copy_table(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    out[k] = v
  end
  return out
end

local function copy_payload(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    if not (type(v) == "table" and v.__dsl_node == true) then
      out[k] = v
    end
  end
  return out
end

local function is_array(tbl)
  if type(tbl) ~= "table" then
    return false
  end
  local has_any = false
  local n = 0
  for k in pairs(tbl) do
    has_any = true
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
    if k > n then
      n = k
    end
  end
  for i = 1, n do
    if tbl[i] == nil then
      return false
    end
  end
  if not has_any then
    return false
  end
  return true
end

local function new_errors()
  return {
    list = {},
    add = function(self, msg, ...)
      table.insert(self.list, string.format(msg, ...))
    end,
    ok = function(self)
      return #self.list == 0
    end,
  }
end

local function node(kind, name, payload)
  return {
    __dsl_node = true,
    kind = kind,
    name = name,
    payload = payload or {},
  }
end

local function is_node(v, kind)
  return type(v) == "table" and v.__dsl_node == true and (not kind or v.kind == kind)
end

local function pop_child(tbl, kind, errs, where)
  local found = nil
  for _, v in ipairs(tbl or {}) do
    if is_node(v, kind) then
      if found then
        errs:add("Duplicate block '%s' in %s.", kind, where)
      else
        found = v
      end
    end
  end
  return found
end

local function collect_children(tbl, kind)
  local out = {}
  for _, v in ipairs(tbl or {}) do
    if is_node(v, kind) then
      table.insert(out, v)
    end
  end
  return out
end

local function parse_duration_seconds(v)
  if type(v) == "number" then
    return v
  end
  if type(v) ~= "string" then
    return nil
  end
  local n, unit = string.match(v, "^([0-9]+%.?[0-9]*)([a-z]+)$")
  n = tonumber(n)
  if not n then
    return tonumber(v)
  end
  if unit == "ms" then
    return n / 1000
  elseif unit == "s" then
    return n
  elseif unit == "m" then
    return n * 60
  elseif unit == "h" then
    return n * 3600
  end
  return nil
end

local function sorted_keys(tbl)
  local keys = {}
  for k in pairs(tbl or {}) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function expr_to_number(v, default)
  if type(v) == "number" then
    return v
  end
  if type(v) ~= "table" then
    return default
  end
  if v.__expr == "dist_fixed" and type(v.value) == "number" then
    return v.value
  end
  if v.__expr == "dist_uniform" and type(v.min) == "number" and type(v.max) == "number" then
    return (v.min + v.max) / 2
  end
  return default
end

local function int_or_default(v, default)
  if type(v) == "number" then
    if v < 0 then
      return default
    end
    return math.floor(v + 0.5)
  end
  return default
end

local function bool_or_default(v, default)
  if type(v) == "boolean" then
    return v
  end
  return default
end

local function string_or_default(v, default)
  if type(v) == "string" and v ~= "" then
    return v
  end
  return default
end

local function map_firewall(v)
  if v == "stateful-lite" or v == "none" then
    return v
  end
  if type(v) == "boolean" then
    return v and "stateful-lite" or "none"
  end
  return "stateful-lite"
end

local function map_transport(v)
  if v == "tcp-lite" or v == "pseudo-udp" or v == "sctp-descriptor" then
    return v
  end
  if v == "tcp" or v == "https" or v == "http" then
    return "tcp-lite"
  end
  if v == "udp" then
    return "pseudo-udp"
  end
  if v == "sctp" then
    return "sctp-descriptor"
  end
  return "tcp-lite"
end

local function pick_profile_by_kind(profiles, wanted_kind)
  local wanted = string.upper(wanted_kind or "")
  for _, name in ipairs(sorted_keys(profiles)) do
    local p = profiles[name]
    if type(p) == "table" and string.upper(tostring(p.kind or "")) == wanted then
      return name, p
    end
  end
  for _, name in ipairs(sorted_keys(profiles)) do
    return name, profiles[name]
  end
  return nil, nil
end

local function normalize_apps(apps)
  if type(apps) ~= "table" then
    return {
      { name = "http", weight = 60 },
      { name = "https", weight = 25 },
      { name = "dns", weight = 15 },
    }
  end
  local out = {}
  local names = {}
  for i, v in ipairs(apps) do
    if type(v) == "string" and v ~= "" then
      names[#names + 1] = v
    elseif type(v) == "table" and type(v.name) == "string" and v.name ~= "" then
      local weight = int_or_default(v.weight, 1)
      if weight < 1 then
        weight = 1
      elseif weight > 100 then
        weight = 100
      end
      out[#out + 1] = { name = v.name, weight = weight }
    end
  end

  if #out == 0 and #names > 0 then
    local base = math.floor(100 / #names)
    if base < 1 then
      base = 1
    end
    local rem = 100 - base * #names
    for i, n in ipairs(names) do
      local w = base
      if rem > 0 then
        w = w + 1
        rem = rem - 1
      end
      out[#out + 1] = { name = n, weight = w }
    end
  end

  if #out == 0 then
    out = {
      { name = "http", weight = 60 },
      { name = "https", weight = 25 },
      { name = "dns", weight = 15 },
    }
  end
  return out
end

local function new_phase_callable(name)
  return function(tbl)
    return node("phase", name, tbl or {})
  end
end

local function new_named_block(kind)
  return function(name)
    return function(tbl)
      return node(kind, name, tbl or {})
    end
  end
end

local function new_anon_block(kind)
  return function(tbl)
    return node(kind, nil, tbl or {})
  end
end

local function build_env(ctx)
  local env = {}

  local safe_methods = {
    assert = assert,
    error = error,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    pcall = pcall,
    rawequal = rawequal,
    rawget = rawget,
    rawlen = rawlen,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    unpack = unpack or table.unpack,
    math = math,
    string = string,
    table = table,
  }
  setmetatable(env, { __index = safe_methods })

  env.dist = {
    uniform = function(a, b)
      return { __expr = "dist_uniform", min = a, max = b }
    end,
    fixed = function(v)
      return { __expr = "dist_fixed", value = v }
    end,
    lognormal = function(mu, sigma)
      return { __expr = "dist_lognormal", mu = mu, sigma = sigma }
    end,
  }

  env.use_profile = function(ref)
    return { __expr = "use_profile", ref = ref }
  end

  env.test = function(name)
    return function(tbl)
      local n = node("test", name, tbl or {})
      ctx.root = n
      return n
    end
  end

  env.equipment = new_anon_block("equipment")
  env.profile = new_named_block("profile")
  env.behavior = new_anon_block("behavior")

  env.topology = new_anon_block("topology")
  env.instances = new_anon_block("instances")
  env.addressing = new_anon_block("addressing")
  env.placement = new_anon_block("placement")

  env.graph = new_anon_block("graph")
  env.graphs = new_anon_block("graphs")
  env.features = new_anon_block("features")
  env.graph_template = new_named_block("graph_template")

  env.traffic = new_anon_block("traffic")
  env.application = new_named_block("application")
  env.app = new_named_block("application")
  env.tcp_model = new_anon_block("tcp_model")

  env.logic = new_anon_block("logic")
  env.populations = new_anon_block("populations")
  env.pacing = new_anon_block("pacing")
  env.tcp_behavior = new_anon_block("tcp_behavior")

  env.phases = new_anon_block("phases")
  env.start = new_phase_callable("start")
  env.steady = new_phase_callable("steady")
  env.finish = new_phase_callable("finish")
  env.phase_end = new_phase_callable("end")

  local ramp_obj = {}
  setmetatable(ramp_obj, {
    __call = function(_, tbl)
      return node("phase", "ramp", tbl or {})
    end,
  })
  ramp_obj.linear = function(a, b)
    return { __expr = "ramp_linear", from = a, to = b }
  end
  env.ramp = ramp_obj

  env.observability = new_anon_block("observability")
  env.acceptance = new_anon_block("acceptance")

  return env
end

local function decode_profiles(block, errs)
  local profiles = {}
  for _, p in ipairs(collect_children(block.payload, "profile")) do
    if profiles[p.name] then
      errs:add("Duplicate profile '%s'.", p.name)
    else
      local data = copy_payload(p.payload)
      local behavior = pop_child(p.payload, "behavior", errs, ("profile '%s'"):format(p.name))
      if behavior then
        data.behavior = behavior.payload
      end
      profiles[p.name] = data
    end
  end
  return profiles
end

local function decode_topology(block, errs)
  local out = copy_payload(block.payload)

  local instances = pop_child(block.payload, "instances", errs, "topology")
  local addressing = pop_child(block.payload, "addressing", errs, "topology")
  local placement = pop_child(block.payload, "placement", errs, "topology")

  out.instances = instances and instances.payload or {}
  out.addressing = addressing and addressing.payload or {}
  out.placement = placement and placement.payload or {}

  return out
end

local function decode_graph(block, errs)
  local out = copy_payload(block.payload)
  local features = pop_child(block.payload, "features", errs, "graph")
  if features then
    out.features = features.payload
  end
  return out
end

local function decode_traffic(block)
  local out = copy_payload(block.payload)
  local apps = {}
  for _, app in ipairs(collect_children(block.payload, "application")) do
    apps[app.name] = copy_payload(app.payload)
  end
  out.applications = apps

  local tcp_model = pop_child(block.payload, "tcp_model", new_errors(), "traffic")
  out.tcp_model = tcp_model and tcp_model.payload or {}
  return out
end

local function decode_logic(block, errs)
  local out = copy_payload(block.payload)
  local populations = pop_child(block.payload, "populations", errs, "logic")
  local pacing = pop_child(block.payload, "pacing", errs, "logic")
  local tcp_behavior = pop_child(block.payload, "tcp_behavior", errs, "logic")

  out.populations = populations and populations.payload or {}
  out.pacing = pacing and pacing.payload or {}
  out.tcp_behavior = tcp_behavior and tcp_behavior.payload or {}
  return out
end

local function decode_phases(block, errs)
  local phases = {}
  local seen = {}
  for _, p in ipairs(collect_children(block.payload, "phase")) do
    if seen[p.name] then
      errs:add("Duplicate phase '%s'.", p.name)
    end
    seen[p.name] = true
    table.insert(phases, { name = p.name, config = copy_payload(p.payload) })
  end
  return phases
end

local function normalize_from_root(root, errs)
  if not root or not is_node(root, "test") then
    errs:add("Scenario file must define exactly one 'test \"name\" { ... }' root block.")
    return nil
  end

  local scenario = {
    scenario_id = root.name,
    mode = root.payload.mode,
    blocks = {},
    raw = copy_payload(root.payload),
  }

  local equipment = pop_child(root.payload, "equipment", errs, "test")
  local topology = pop_child(root.payload, "topology", errs, "test")
  local graph = pop_child(root.payload, "graph", errs, "test")
  local traffic = pop_child(root.payload, "traffic", errs, "test")
  local logic = pop_child(root.payload, "logic", errs, "test")
  local phases = pop_child(root.payload, "phases", errs, "test")
  local observability = pop_child(root.payload, "observability", errs, "test")
  local acceptance = pop_child(root.payload, "acceptance", errs, "test")

  scenario.blocks.equipment = equipment and { profiles = decode_profiles(equipment, errs) } or { profiles = {} }
  scenario.blocks.topology = topology and decode_topology(topology, errs) or {}
  scenario.blocks.graph = graph and decode_graph(graph, errs) or {}
  scenario.blocks.traffic = traffic and decode_traffic(traffic, errs) or { applications = {}, tcp_model = {} }
  scenario.blocks.logic = logic and decode_logic(logic, errs) or { populations = {}, pacing = {}, tcp_behavior = {} }
  scenario.blocks.phases = phases and decode_phases(phases, errs) or {}
  scenario.blocks.observability = observability and copy_payload(observability.payload) or {}
  scenario.blocks.acceptance = acceptance and copy_payload(acceptance.payload) or {}

  return scenario
end

local function run_chunk(loader, chunkname)
  local ctx = { root = nil }
  local env = build_env(ctx)

  local f, load_err = loader()
  if not f then
    return nil, { load_err }
  end
  setfenv(f, env)

  local ok, runtime_err = pcall(f)
  if not ok then
    return nil, { runtime_err }
  end

  local errs = new_errors()
  local scenario = normalize_from_root(ctx.root, errs)
  if not errs:ok() then
    return nil, errs.list
  end
  return scenario, nil
end

function M.parse_string(source, chunkname)
  return run_chunk(function()
    return loadstring(source, chunkname or "scenario_dsl")
  end, chunkname or "scenario_dsl")
end

function M.parse_file(path)
  return run_chunk(function()
    return loadfile(path)
  end, path)
end

function M.validate(scenario)
  local errs = new_errors()
  if type(scenario) ~= "table" then
    errs:add("Scenario object is missing.")
    return false, errs.list
  end

  if type(scenario.scenario_id) ~= "string" or scenario.scenario_id == "" then
    errs:add("Scenario id is required.")
  end

  if scenario.mode and scenario.mode ~= "1-arm" and scenario.mode ~= "2-arm" then
    errs:add("Scenario mode must be '1-arm' or '2-arm' when set.")
  end

  local blocks = scenario.blocks or {}
  local profiles = ((blocks.equipment or {}).profiles or {})
  if next(profiles) == nil then
    errs:add("At least one equipment profile is required.")
  end

  local topology = blocks.topology or {}
  local instances = topology.instances or {}
  local cpe_count = topology.cpe_count or instances.cpe
  if cpe_count ~= nil and (type(cpe_count) ~= "number" or cpe_count <= 0) then
    errs:add("Topology cpe_count must be a positive number.")
  end

  local traffic = blocks.traffic or {}
  local applications = traffic.applications or {}
  if next(applications) == nil then
    errs:add("At least one traffic application is required.")
  end

  local engine = (traffic.tcp_model or {}).engine or (blocks.graph or {}).transport_engine
  if engine and engine ~= "microflow" and engine ~= "vpp" and engine ~= "stub" then
    errs:add("Unsupported transport engine '%s'.", tostring(engine))
  end

  local required = { start = true, ramp = true, steady = true, finish = true }
  local found = {}
  for _, phase in ipairs(blocks.phases or {}) do
    local name = phase.name
    found[name] = true
    local raw_duration = phase.config and phase.config.duration
    local duration_s = parse_duration_seconds(raw_duration)
    if raw_duration == nil and name == "end" then
      duration_s = 0
    end
    if duration_s == nil then
      errs:add("Phase '%s' has invalid duration '%s'.", tostring(name), tostring(raw_duration))
    elseif duration_s < 0 then
      errs:add("Phase '%s' duration cannot be negative.", tostring(name))
    end
  end
  for name in pairs(required) do
    if not found[name] then
      errs:add("Missing mandatory phase '%s'.", name)
    end
  end

  return errs:ok(), errs.list
end

local function normalize_target_cps(cfg)
  local v = cfg.target_cps or cfg.hold_cps or cfg.cps
  if type(v) == "table" and v.__expr == "ramp_linear" then
    return { kind = "linear", from = v.from, to = v.to }
  end
  return v
end

function M.compile(scenario)
  local ok, errors = M.validate(scenario)
  if not ok then
    return nil, errors
  end

  local blocks = scenario.blocks
  local graph = blocks.graph or {}
  local traffic = blocks.traffic or {}
  local logic = blocks.logic or {}
  local topology = blocks.topology or {}
  local instances = topology.instances or {}

  local engine = (traffic.tcp_model or {}).engine or graph.transport_engine or "microflow"
  local fidelity = (traffic.tcp_model or {}).fidelity or "medium"

  local phases = {}
  local offset_s = 0
  for _, phase in ipairs(blocks.phases or {}) do
    local duration_s = parse_duration_seconds(phase.config.duration)
    if duration_s == nil and phase.name == "end" then
      duration_s = 0
    end
    duration_s = duration_s or 0
    table.insert(phases, {
      name = phase.name,
      offset_s = offset_s,
      duration_s = duration_s,
      target_cps = normalize_target_cps(phase.config),
      actions = phase.config.actions,
      drain = phase.config.drain,
      cleanup = phase.config.cleanup,
      export = phase.config.export,
    })
    offset_s = offset_s + duration_s
  end

  local plan = {
    version = "1.0.0",
    scenario_id = scenario.scenario_id,
    mode = scenario.mode or "2-arm",
    engine = engine,
    fidelity = fidelity,
    graph = {
      template = graph.template,
      features = graph.features or {},
    },
    populations = {
      cpe_count = topology.cpe_count or instances.cpe,
      ue_per_cpe = topology.ue_per_cpe or instances.ue_per_cpe,
      servers = instances.servers,
      public_ips = (logic.populations or {}).public_ips,
      ue_count = (logic.populations or {}).ue_count,
    },
    placement = topology.placement or {},
    addressing = topology.addressing or {},
    applications = traffic.applications or {},
    tcp_model = traffic.tcp_model or {},
    logic = logic,
    observability = blocks.observability or {},
    acceptance = blocks.acceptance or {},
    phases = phases,
    timeline_duration_s = offset_s,
  }

  return plan, nil
end

function M.to_scenario_v1(scenario, plan)
  if not plan then
    local plan_err
    plan, plan_err = M.compile(scenario)
    if not plan then
      return nil, plan_err
    end
  end

  local blocks = scenario and scenario.blocks or {}
  local profiles = ((blocks.equipment or {}).profiles or {})
  local cpe_name, cpe_profile = pick_profile_by_kind(profiles, "CPE")
  local ue_name, ue_profile = pick_profile_by_kind(profiles, "UE")
  cpe_profile = cpe_profile or {}
  ue_profile = ue_profile or {}

  local ue_behavior = type(ue_profile.behavior) == "table" and ue_profile.behavior or {}
  local apps = normalize_apps(ue_profile.apps)
  local parallel_sessions = int_or_default(
    expr_to_number(ue_behavior.parallel_sessions, ue_profile.parallel_sessions),
    2
  )
  if parallel_sessions < 1 then
    parallel_sessions = 1
  end

  local populations = plan.populations or {}
  local addressing = plan.addressing or {}
  local placement = plan.placement or {}
  local graph_features = (plan.graph or {}).features or {}
  local traffic_apps = plan.applications or {}

  local first_app = nil
  for _, name in ipairs(sorted_keys(traffic_apps)) do
    first_app = traffic_apps[name]
    break
  end
  first_app = first_app or {}

  local cpe_count = int_or_default(populations.cpe_count, 1)
  if cpe_count < 1 then
    cpe_count = 1
  end

  local ue_per_cpe = int_or_default(expr_to_number(populations.ue_per_cpe, cpe_profile.ue_per_cpe), 1)
  if ue_per_cpe < 1 then
    ue_per_cpe = 1
  end

  local top = {
    cpe_count = cpe_count,
    public_ip_pool = string_or_default(addressing.wan_pool, "100.64.0.0/12"),
    server_pool = string_or_default(addressing.server_pool, "10.10.0.0/16"),
    shard_by = (placement.shard_by == "ue") and "ue" or "cpe",
  }

  if type(addressing.vlan_id) == "number" then
    top.vlan_id = int_or_default(addressing.vlan_id, nil)
  end
  if type(addressing.vrf) == "string" and addressing.vrf ~= "" then
    top.vrf = addressing.vrf
  end
  if type(placement.sriov) == "table" then
    top.sriov = {
      enabled = bool_or_default(placement.sriov.enabled, false),
      vf_per_port = int_or_default(placement.sriov.vf_per_port, nil),
    }
    if top.sriov.vf_per_port == nil then
      top.sriov.vf_per_port = 1
    end
  end

  local traffic = {
    transport = map_transport(first_app.transport),
    dst_port = int_or_default(first_app.dst_port, 80),
    request_model = string_or_default(first_app.request_model, "http-get-lite"),
    ip_family = string_or_default(first_app.ip_family, "ipv4"),
  }
  if traffic.dst_port < 1 then
    traffic.dst_port = 80
  elseif traffic.dst_port > 65535 then
    traffic.dst_port = 65535
  end

  local tcp_model = plan.tcp_model or {}
  local logic = {
    tcp = {
      init_cwnd = int_or_default(tcp_model.init_cwnd, 10),
      max_retries_setup = int_or_default(tcp_model.max_retries_setup, 3),
      sack = bool_or_default(tcp_model.sack, false),
    },
    addressing = {
      source_ip_policy = "per-ue",
      source_port_policy = "ephemeral",
    }
  }

  if logic.tcp.init_cwnd < 1 then
    logic.tcp.init_cwnd = 1
  end
  if logic.tcp.max_retries_setup < 0 then
    logic.tcp.max_retries_setup = 0
  end

  local phases = {}
  for _, p in ipairs(plan.phases or {}) do
    local item = {
      name = p.name,
      duration_s = p.duration_s or 0,
    }
    if p.target_cps ~= nil then
      if type(p.target_cps) == "number" then
        item.target_cps = p.target_cps
      elseif type(p.target_cps) == "table" and p.target_cps.kind == "linear" then
        item.target_cps = p.target_cps.to or p.target_cps.from
      end
    end
    table.insert(phases, item)
  end

  local seen = {}
  for _, p in ipairs(phases) do
    seen[p.name] = true
  end
  if not seen["end"] then
    table.insert(phases, { name = "end", duration_s = 0 })
  end

  local acceptance_cfg = blocks.acceptance or {}
  local acceptance = {
    max_drop_rate = acceptance_cfg.max_drop_rate or 0.0,
    max_latency_us_p95 = acceptance_cfg.max_latency_us_p95 or 1200.0,
    max_tcp_retries_setup = acceptance_cfg.max_tcp_retries_setup or logic.tcp.max_retries_setup,
  }

  local out = {
    schema_version = "1.0.0",
    scenario_id = scenario.scenario_id,
    mode = plan.mode or "2-arm",
    profiles = {
      cpe = {
        name = cpe_name or "virtual_cpe",
        nat44 = bool_or_default(cpe_profile.nat44, bool_or_default(graph_features.nat44, true)),
        firewall = map_firewall(cpe_profile.firewall ~= nil and cpe_profile.firewall or graph_features.firewall),
        ue_per_cpe = ue_per_cpe,
      },
      ue = {
        name = ue_name or "virtual_ue",
        parallel_sessions = parallel_sessions,
        apps = apps,
      }
    },
    topology = top,
    traffic = traffic,
    logic = logic,
    phases = phases,
    acceptance = acceptance,
  }

  return out, nil
end

function M.load_and_compile_file(path)
  local scenario, parse_errors = M.parse_file(path)
  if not scenario then
    return nil, parse_errors
  end
  return M.compile(scenario)
end

function M.is_array(v)
  return is_array(v)
end

return M
