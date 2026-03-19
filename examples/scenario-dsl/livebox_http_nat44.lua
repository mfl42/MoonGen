test "livebox_http_nat44" {
  mode = "2-arm",

  equipment {
    profile "cpe_livebox" {
      kind = "CPE",
      variants = {
        { wan = "dhcp", lan = "192.168.1.0/24", nat44 = true, firewall = true },
        { wan = "pppoe", lan = "192.168.10.0/24", nat44 = true, firewall = true }
      }
    },

    profile "ue_android" {
      kind = "UE",
      os = "android",
      apps = { "http", "https", "dns" },
      behavior {
        parallel_sessions = dist.uniform(1, 8),
        reconnect_policy = "bursty",
        idle_ratio = 0.65
      }
    },

    profile "ue_linux" {
      kind = "UE",
      os = "linux",
      apps = { "http", "iperf" }
    }
  },

  topology {
    instances {
      cpe = 500,
      ue_per_cpe = dist.uniform(8, 32),
      servers = 12
    },

    arms {
      traversal = "cross-arm",
      traffic_direction = "full_duplex",
      left_port_index = 0,
      right_port_index = 1,
      left_role = "client",
      right_role = "server"
    },

    addressing {
      wan_pool = "100.64.0.0/12",
      server_pool = "10.200.0.0/16",
      ue_lan_per_cpe = true
    },

    placement {
      shard_by = "cpe",
      affinity = "queue_core_strict"
    }
  },

  graph {
    template = "tcp_nat44_firewall",
    transport_engine = "microflow",
    features = {
      nat44 = true,
      firewall = true,
      ipsec = false,
      gtpu = false
    }
  },

  traffic {
    application "web_browsing" {
      transport = "tcp",
      dst_port = 80,
      object_size = dist.lognormal("32KB", "512KB"),
      think_time = dist.uniform("300ms", "5s"),
      concurrency_per_ue = dist.uniform(1, 6)
    },

    tcp_model {
      engine = "microflow",
      fidelity = "medium",
      handshake = true,
      slow_start = true,
      init_cwnd = 10,
      rto = "adaptive-lite",
      sack = false,
      timestamps = false
    }
  },

  logic {
    populations {
      public_ips = 64,
      cpe_count = 500,
      ue_count = 8000
    },

    pacing {
      connection_rate = "adaptive",
      burstiness = 0.2
    },

    tcp_behavior {
      slow_start = true,
      cwnd_growth = "reno-lite"
    }
  },

  phases {
    start {
      duration = "10s",
      actions = { "warmup_arp", "warmup_routes" }
    },

    ramp {
      duration = "60s",
      target_cps = 200000
    },

    steady {
      duration = "300s",
      hold_cps = 200000
    },

    finish {
      duration = "20s",
      drain = true
    },

    phase_end {
      cleanup = true,
      export = { "latency", "errors", "flows" }
    }
  },

  acceptance {
    max_drop_rate = 0.0,
    max_latency_us_p95 = 1200,
    max_tcp_retries_setup = 3
  },

  observability {
    per_worker = true,
    histograms = { "rtt", "ttfb", "flow_duration" },
    counters = { "syn", "synack", "ack", "rst", "timeout" }
  }
}
