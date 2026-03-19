test "client_1arm_real_servers" {
  mode = "1-arm",

  equipment {
    profile "ue_home_standard" {
      kind = "UE",
      apps = {
        { name = "dns", weight = 20 },
        { name = "http", weight = 50 },
        { name = "https", weight = 25 },
        { name = "ntp", weight = 5 }
      },
      behavior {
        parallel_sessions = dist.uniform(1, 6),
        reconnect_policy = "bursty",
        idle_ratio = 0.7
      }
    }
  },

  topology {
    instances {
      cpe = 1,
      ue_per_cpe = 20000,
      servers = 64
    },

    addressing {
      wan_pool = "100.64.0.0/12",
      server_pool = "10.10.0.0/16"
    },

    placement {
      shard_by = "ue",
      affinity = "queue_core_strict"
    }
  },

  graph {
    template = "tcp_nat44_firewall",
    transport_engine = "microflow"
  },

  traffic {
    application "superflow_web_mix" {
      transport = "tcp",
      dst_port = 443,
      request_model = "http-get-lite",
      think_time = dist.uniform("200ms", "2s")
    },

    tcp_model {
      engine = "microflow",
      fidelity = "medium",
      init_cwnd = 10,
      max_retries_setup = 3,
      sack = false
    }
  },

  phases {
    start { duration = "10s" },
    ramp { duration = "45s", cps = ramp.linear(0, 150000) },
    steady { duration = "180s", hold_cps = 150000 },
    finish { duration = "20s", drain = true },
    phase_end { cleanup = true, export = { "latency", "success", "timeouts", "retries" } }
  },

  observability {
    per_worker = true,
    counters = { "syn", "synack", "ack", "rst", "timeout" }
  }
}
