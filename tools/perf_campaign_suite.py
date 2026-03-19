#!/usr/bin/env python3
"""
Run multi-KPI performance campaigns with scaling, regression checks, and a
human-readable report.

This tool drives `vmoongenctl scenario-campaign-cache` for each KPI/factor case.
Outputs in suite directory:
  - report_campaign.txt
  - report_campaign.json
  - scenarios/*.lua
  - campaigns/<kpi>/x<factor>/*
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


SUPPORTED_KPIS = (
    "max_cps_tcp",
    "max_sessions_50pct_cps",
    "max_bandwidth_tcp",
    "max_bandwidth_udp",
)


@dataclass
class CaseResult:
    status: str
    kpi: str
    factor: int
    terminals: int
    seed_cps: int
    run_window: str
    case_dir: Path
    scenario_file: Path
    command: List[str]
    best_cps: float = 0.0
    observed_cps: float = 0.0
    drop_rate: float = 1.0
    latency_p95_us: float = 0.0
    retries_total: float = 0.0
    concurrent_sessions: float = 0.0
    observed_bandwidth_bps: float = 0.0
    test_duration_s: float = 0.0
    pcap_bytes: int = 0
    pcap_packets: int = 0
    efficiency: Dict[str, Any] = field(default_factory=dict)
    cache_recommendation: str = ""
    warnings: List[str] = field(default_factory=list)
    error: Optional[str] = None


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_duration_seconds(text: str) -> int:
    raw = text.strip().lower()
    if raw.endswith("ms"):
        return max(1, int(float(raw[:-2]) / 1000.0))
    if raw.endswith("s"):
        return max(1, int(float(raw[:-1])))
    if raw.endswith("m"):
        return max(1, int(float(raw[:-1]) * 60.0))
    if raw.endswith("h"):
        return max(1, int(float(raw[:-1]) * 3600.0))
    return max(1, int(float(raw)))


def run_cmd(cmd: List[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        check=True,
        text=True,
        capture_output=True,
    )


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_factors(raw: str) -> List[int]:
    out: List[int] = []
    for part in raw.split(","):
        p = part.strip()
        if not p:
            continue
        v = int(p)
        if v < 1:
            continue
        if v not in out:
            out.append(v)
    if not out:
        out = [1, 2, 4]
    out.sort()
    return out


def parse_kpis(raw: str) -> List[str]:
    out: List[str] = []
    for part in raw.split(","):
        p = part.strip()
        if not p:
            continue
        if p not in SUPPORTED_KPIS:
            raise ValueError(f"Unsupported KPI '{p}'. Allowed: {', '.join(SUPPORTED_KPIS)}")
        if p not in out:
            out.append(p)
    if not out:
        out = list(SUPPORTED_KPIS)
    return out


def shell_join(parts: Iterable[str]) -> str:
    quoted: List[str] = []
    for item in parts:
        s = str(item)
        if s == "":
            quoted.append("''")
        elif any(ch in s for ch in " \t\n'\"$`\\"):
            quoted.append("'" + s.replace("'", "'\\''") + "'")
        else:
            quoted.append(s)
    return " ".join(quoted)


def clamp_seed(seed: int, cap: int) -> int:
    return max(1, min(int(seed), int(cap)))


def cps_from_mbps_per_client(terminals: int, mbps_per_client: float, payload_bytes: int) -> int:
    # Approximation from target bitrate:
    # cps ~= total_bps / (wire_bytes * 8)
    wire_bytes = max(64, int(payload_bytes) + 58)
    total_bps = float(terminals) * float(mbps_per_client) * 1_000_000.0
    cps = int(total_bps / float(wire_bytes * 8))
    return max(1, cps)


def kpi_seed_cps(
    kpi: str,
    terminals: int,
    sessions_per_terminal: int,
    prev_cps_best: Optional[float],
    cps_per_client_override: Optional[int],
    mbps_per_client_override: Optional[float],
    tcp_payload_bytes: int,
    udp_payload_bytes: int,
    seed_cps_cap: int,
) -> int:
    if cps_per_client_override and cps_per_client_override > 0:
        cps_base = max(1, terminals * int(cps_per_client_override))
    else:
        cps_base = max(1, terminals * sessions_per_terminal)

    if kpi == "max_cps_tcp":
        return clamp_seed(cps_base, seed_cps_cap)
    if kpi == "max_sessions_50pct_cps":
        if prev_cps_best and prev_cps_best > 0:
            return clamp_seed(int(prev_cps_best * 0.5), seed_cps_cap)
        return clamp_seed(max(1, cps_base // 2), seed_cps_cap)
    if kpi == "max_bandwidth_tcp":
        if mbps_per_client_override and mbps_per_client_override > 0:
            return clamp_seed(
                cps_from_mbps_per_client(terminals, mbps_per_client_override, tcp_payload_bytes),
                seed_cps_cap,
            )
        return clamp_seed(max(1, terminals * max(8, sessions_per_terminal // 2)), seed_cps_cap)
    if kpi == "max_bandwidth_udp":
        if mbps_per_client_override and mbps_per_client_override > 0:
            return clamp_seed(
                cps_from_mbps_per_client(terminals, mbps_per_client_override, udp_payload_bytes),
                seed_cps_cap,
            )
        return clamp_seed(max(1, terminals * max(10, sessions_per_terminal // 2)), seed_cps_cap)
    return clamp_seed(cps_base, seed_cps_cap)


def window_for_kpi(kpi: str, run_window_general: str, run_window_cps: str) -> str:
    if kpi in ("max_cps_tcp", "max_sessions_50pct_cps"):
        return run_window_cps
    return run_window_general


def scenario_lua(
    scenario_id: str,
    terminals: int,
    seed_cps: int,
    kpi: str,
    tcp_payload_bytes: int,
    udp_payload_bytes: int,
    cpe_count: int,
    ue_per_cpe: int,
    udp_ttl_s: int,
    udp_bidirectional: bool,
) -> str:
    if kpi == "max_cps_tcp":
        apps_block = f"""
    application "a_tcp_short" {{
      transport = "tcp",
      dst_port = 443,
      request_model = "http-get-lite",
      session_weight = 90,
      session_ttl_s = 30,
      object_size = dist.fixed("4KB"),
      think_time = dist.uniform("50ms", "300ms")
    }},

    application "b_dns_short" {{
      transport = "pseudo-udp",
      dst_port = 53,
      request_model = "dns-lite",
      session_weight = 10,
      session_ttl_s = 5,
      object_size = dist.fixed("128B"),
      think_time = dist.uniform("50ms", "200ms")
    }},
"""
    elif kpi == "max_sessions_50pct_cps":
        apps_block = f"""
    application "a_http_long" {{
      transport = "tcp",
      dst_port = 443,
      request_model = "http-get-lite",
      session_weight = 80,
      session_ttl_s = 1800,
      object_size = dist.fixed("128KB"),
      think_time = dist.uniform("200ms", "2s")
    }},

    application "b_dns_short" {{
      transport = "pseudo-udp",
      dst_port = 53,
      request_model = "dns-lite",
      session_weight = 20,
      session_ttl_s = 5,
      object_size = dist.fixed("128B"),
      think_time = dist.uniform("100ms", "500ms")
    }},
"""
    elif kpi == "max_bandwidth_tcp":
        apps_block = f"""
    application "a_http_long" {{
      transport = "tcp",
      dst_port = 443,
      request_model = "http-get-lite",
      session_weight = 70,
      session_ttl_s = 1800,
      object_size = dist.fixed("{tcp_payload_bytes}B"),
      think_time = dist.uniform("50ms", "250ms")
    }},

    application "b_dns_short" {{
      transport = "pseudo-udp",
      dst_port = 53,
      request_model = "dns-lite",
      session_weight = 30,
      session_ttl_s = 5,
      object_size = dist.fixed("128B"),
      think_time = dist.uniform("50ms", "250ms")
    }},
"""
    else:
        apps_block = f"""
    application "a_udp_echo" {{
      transport = "pseudo-udp",
      dst_port = 5001,
      request_model = "udp-echo-lite",
      session_weight = 100,
      session_ttl_s = {udp_ttl_s},
      object_size = dist.fixed("{udp_payload_bytes}B"),
      think_time = dist.uniform("5ms", "25ms")
    }},
"""

    traffic_direction = "full_duplex" if (kpi == "max_bandwidth_udp" and udp_bidirectional) else "client_to_server"
    client_cps_share = 0.5 if traffic_direction == "full_duplex" else 1.0
    server_cps_share = 0.5 if traffic_direction == "full_duplex" else 0.0

    return f"""test "{scenario_id}" {{
  mode = "2-arm",

  equipment {{
    profile "cpe_livebox_nat44" {{
      kind = "CPE",
      nat44 = true,
      firewall = true
    }},

    profile "ue_mix" {{
      kind = "UE",
      apps = {{ "http", "dns" }},
      behavior {{
        parallel_sessions = dist.fixed(2),
        reconnect_policy = "bursty",
        idle_ratio = 0.7
      }}
    }}
  }},

  topology {{
    instances {{
      cpe = {cpe_count},
      ue_per_cpe = dist.fixed({ue_per_cpe}),
      servers = 4
    }},

    arms {{
      traversal = "cross-arm",
      traffic_direction = "{traffic_direction}",
      left_port_index = 0,
      right_port_index = 1,
      left_role = "client",
      right_role = "server"
    }},

    addressing {{
      wan_pool = "100.64.0.0/12",
      server_pool = "10.200.0.0/16",
      ue_lan_per_cpe = true
    }},

    placement {{
      shard_by = "ue",
      affinity = "queue_core_strict"
    }}
  }},

  graph {{
    template = "tcp_nat44_firewall",
    transport_engine = "vpp",
    features = {{
      nat44 = true,
      firewall = true,
      ipsec = false,
      gtpu = false
    }}
  }},

  traffic {{
{apps_block}
    tcp_model {{
      engine = "microflow",
      client_engine = "microflow",
      server_engine = "vpp",
      fidelity = "medium",
      client_fidelity = "medium",
      server_fidelity = "full",
      handshake = true,
      slow_start = true,
      init_cwnd = 10,
      max_retries_setup = 3,
      sack = false
    }}
  }},

  logic {{
    populations {{
      public_ips = {cpe_count},
      cpe_count = {cpe_count},
      ue_count = {terminals}
    }},

    pacing {{
      connection_rate = "adaptive",
      burstiness = 0.1,
      client_cps_share = {client_cps_share},
      server_cps_share = {server_cps_share}
    }}
  }},

  phases {{
    start {{ duration = "5s", actions = {{ "warmup_arp", "warmup_routes" }} }},
    ramp {{ duration = "10s", target_cps = {seed_cps} }},
    steady {{ duration = "30s", hold_cps = {seed_cps} }},
    finish {{ duration = "5s", drain = true }},
    phase_end {{ cleanup = true, export = {{ "latency", "errors", "flows" }} }}
  }},

  acceptance {{
    max_drop_rate = 0.0,
    max_latency_us_p95 = 1200,
    max_tcp_retries_setup = 3
  }},

  observability {{
    per_worker = true,
    histograms = {{ "rtt", "ttfb", "flow_duration" }},
    counters = {{ "syn", "synack", "ack", "rst", "timeout" }}
  }}
}}
"""


def parse_case_metrics(case_dir: Path) -> Tuple[float, float, float, float, float, float, float, float]:
    campaign = load_json(case_dir / "campaign-results.json")
    best_info = campaign.get("best_known") or {}
    best_run_id = best_info.get("run_id")
    best_cps = float(best_info.get("value") or 0.0)

    run_entry = None
    for run in campaign.get("runs") or []:
        if best_run_id and run.get("run_id") == best_run_id:
            run_entry = run
            break
    if run_entry is None:
        for run in campaign.get("runs") or []:
            if run.get("verdict") == "pass":
                run_entry = run
                break
    if run_entry is None:
        runs = campaign.get("runs") or []
        run_entry = runs[0] if runs else None
    if not run_entry:
        return best_cps, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0

    run_dir = run_entry.get("artifact_dir")
    if not run_dir:
        candidate = int(run_entry.get("candidate_value") or 0)
        idx = 1
        for i, row in enumerate(campaign.get("runs") or [], start=1):
            if row is run_entry:
                idx = i
                break
        run_dir = str(case_dir / "runs" / f"{idx:03d}-{candidate}")

    run_summary = load_json(Path(run_dir) / "run-summary.json")
    m = run_summary.get("metrics") or {}
    observed_cps = float(m.get("cps") or 0.0)
    drop_rate = float(m.get("drop_rate") or 0.0)
    latency = float(m.get("latency_us_p95") or 0.0)
    retries = float(m.get("tcp_retries_total") or 0.0)
    concurrent = float(m.get("concurrent_sessions") or 0.0)
    observed_bw = float(m.get("bandwidth_bps") or m.get("throughput_bps") or 0.0)
    timing = run_summary.get("timing") or {}
    test_duration_s = float(timing.get("test_duration_s") or timing.get("phase_window_s") or 0.0)
    return best_cps, observed_cps, drop_rate, latency, retries, concurrent, observed_bw, test_duration_s


def parse_pcap_summary(case_dir: Path) -> Tuple[int, int]:
    pcap_bytes = 0
    pcap_packets = 0
    pcap_file = case_dir / "campaign-capture.pcap"
    if pcap_file.exists():
        try:
            pcap_bytes = int(pcap_file.stat().st_size)
        except Exception:
            pcap_bytes = 0

    trim_log = case_dir / "pcap-trim.log"
    if trim_log.exists():
        try:
            text = trim_log.read_text(encoding="utf-8", errors="replace")
            for token in text.replace("\n", " ").split():
                if token.startswith("packets="):
                    pcap_packets = int(token.split("=", 1)[1])
                elif token.startswith("bytes=") and pcap_bytes <= 0:
                    pcap_bytes = int(token.split("=", 1)[1])
        except Exception:
            pass
    return pcap_bytes, pcap_packets


def primary_metric(result: CaseResult) -> float:
    if result.kpi == "max_bandwidth_tcp":
        return result.observed_bandwidth_bps
    if result.kpi == "max_bandwidth_udp":
        return result.observed_bandwidth_bps
    if result.kpi == "max_sessions_50pct_cps":
        return result.concurrent_sessions
    return result.best_cps


def per_terminal_metric(result: CaseResult) -> float:
    return primary_metric(result) / max(1, result.terminals)


def format_metric(kpi: str, value: float) -> str:
    if kpi in ("max_bandwidth_tcp", "max_bandwidth_udp"):
        if value >= 1_000_000_000:
            return f"{value / 1_000_000_000:.3f} Gbps"
        if value >= 1_000_000:
            return f"{value / 1_000_000:.3f} Mbps"
        return f"{value:.2f} bps"
    return f"{value:.3f}"


def regression_checks_within_campaign(
    results: List[CaseResult],
    threshold: float,
) -> List[str]:
    findings: List[str] = []
    grouped: Dict[str, List[CaseResult]] = {}
    for row in results:
        if row.status != "ok":
            continue
        grouped.setdefault(row.kpi, []).append(row)
    for kpi, rows in grouped.items():
        rows.sort(key=lambda x: x.factor)
        previous: Optional[CaseResult] = None
        for current in rows:
            if previous is None:
                previous = current
                continue
            prev_norm = per_terminal_metric(previous)
            cur_norm = per_terminal_metric(current)
            if prev_norm > 0:
                drop = (prev_norm - cur_norm) / prev_norm
                if drop > threshold:
                    findings.append(
                        f"{kpi}: x{previous.factor} -> x{current.factor} "
                        f"per-terminal metric dropped by {drop * 100:.2f}% "
                        f"(threshold {threshold * 100:.1f}%)"
                    )
            previous = current
    return findings


def regression_checks_against_baseline(
    results: List[CaseResult],
    baseline_path: Optional[Path],
    threshold: float,
) -> Tuple[List[str], Optional[Dict[str, Any]]]:
    if not baseline_path:
        return [], None
    if not baseline_path.exists():
        return [f"baseline report not found: {baseline_path}"], None
    data = load_json(baseline_path)
    index: Dict[Tuple[str, int], Dict[str, Any]] = {}
    for row in data.get("results") or []:
        key = (str(row.get("kpi") or ""), int(row.get("factor") or 0))
        index[key] = row

    findings: List[str] = []
    for row in results:
        if row.status != "ok":
            continue
        key = (row.kpi, row.factor)
        b = index.get(key)
        if not b:
            continue
        if row.kpi in ("max_bandwidth_tcp", "max_bandwidth_udp"):
            old = float(b.get("observed_bandwidth_bps") or 0.0)
            new = row.observed_bandwidth_bps
        elif row.kpi == "max_sessions_50pct_cps":
            old = float(b.get("concurrent_sessions") or 0.0)
            new = row.concurrent_sessions
        else:
            old = float(b.get("best_cps") or 0.0)
            new = row.best_cps
        if old <= 0:
            continue
        drop = (old - new) / old
        if drop > threshold:
            findings.append(
                f"{row.kpi} factor x{row.factor}: baseline -> current dropped by "
                f"{drop * 100:.2f}% (threshold {threshold * 100:.1f}%)"
            )
    return findings, data


def case_analysis_notes(result: CaseResult) -> List[str]:
    out: List[str] = []
    if result.status != "ok":
        out.append("blocked: campaign execution failed, see case-run.log and case-stderr.log")
        return out
    if result.drop_rate > 0:
        out.append("packet loss detected: tune cps candidate envelope or increase queue/buffer depth")
    if result.latency_p95_us > 1200:
        out.append("latency p95 above acceptance: check worker affinity and reduce per-flow state churn")
    if result.retries_total > 0:
        out.append("tcp retries present: inspect timeout policy and pacing aggressiveness")
    if result.cache_recommendation:
        out.append(f"cache guidance: {result.cache_recommendation}")
    if not out:
        out.append("no immediate blocker from acceptance metrics in this case")
    return out


def build_report(
    out_dir: Path,
    results: List[CaseResult],
    regressions_within: List[str],
    regressions_baseline: List[str],
    config: Dict[str, Any],
    blocked_cases: List[str],
    baseline_payload: Optional[Dict[str, Any]],
) -> None:
    now = utc_now()
    lines: List[str] = []
    lines.append("vMoonGen performance campaign report")
    lines.append(f"generated_at_utc: {now}")
    lines.append(f"output_dir: {out_dir}")
    lines.append("")
    lines.append("configuration:")
    for key in sorted(config.keys()):
        lines.append(f"  {key}: {config[key]}")
    lines.append("")
    lines.append("campaign_results:")
    for row in results:
        lines.append(
            f"  - status={row.status} kpi={row.kpi} factor=x{row.factor} terminals={row.terminals} "
            f"seed_cps={row.seed_cps} run_window={row.run_window}"
        )
        if row.status == "ok":
            lines.append(
                f"    primary_metric={format_metric(row.kpi, primary_metric(row))} "
                f"per_terminal={per_terminal_metric(row):.6f}"
            )
            lines.append(
                f"    best_cps={row.best_cps:.3f} observed_cps={row.observed_cps:.3f} "
                f"drop_rate={row.drop_rate:.6f} latency_p95_us={row.latency_p95_us:.3f} "
                f"concurrent_sessions={row.concurrent_sessions:.3f} "
                f"observed_bandwidth_bps={row.observed_bandwidth_bps:.3f}"
            )
            lines.append(f"    test_duration_s={row.test_duration_s:.3f}")
            lines.append(f"    pcap_bytes={row.pcap_bytes} pcap_packets={row.pcap_packets}")
            for note in case_analysis_notes(row):
                lines.append(f"    analysis: {note}")
            for warn in row.warnings:
                lines.append(f"    warning: {warn}")
        else:
            lines.append(f"    error: {row.error}")
        lines.append(f"    scenario: {row.scenario_file}")
        lines.append(f"    artifacts: {row.case_dir}")
        lines.append(f"    command: {shell_join(row.command)}")
    lines.append("")

    lines.append("regression_within_campaign:")
    if regressions_within:
        for item in regressions_within:
            lines.append(f"  - {item}")
    else:
        lines.append("  - none detected")
    lines.append("")

    lines.append("regression_vs_baseline:")
    if baseline_payload is None:
        lines.append("  - baseline not provided")
    elif regressions_baseline:
        for item in regressions_baseline:
            lines.append(f"  - {item}")
    else:
        lines.append("  - none detected")
    lines.append("")

    lines.append("blocked_cases:")
    if blocked_cases:
        for item in blocked_cases:
            lines.append(f"  - {item}")
    else:
        lines.append("  - none")
    lines.append("")

    lines.append("optimization_loop_notes:")
    lines.append("  - Use x2 factors first, then optional x10 overload once metrics stay stable.")
    lines.append("  - If overload fails, backtrack with campaign dichotomy bounds and rerun.")
    lines.append("  - Keep this suite as regular non-regression with a saved baseline report_campaign.json.")
    lines.append("  - Prioritize 2-arm path; run 1-arm only after 2-arm KPI envelope is stable.")
    write_text(out_dir / "report_campaign.txt", "\n".join(lines) + "\n")

    payload = {
        "generated_at_utc": now,
        "config": config,
        "results": [
            {
                "status": row.status,
                "kpi": row.kpi,
                "factor": row.factor,
                "terminals": row.terminals,
                "seed_cps": row.seed_cps,
                "run_window": row.run_window,
                "best_cps": row.best_cps,
                "observed_cps": row.observed_cps,
                "drop_rate": row.drop_rate,
                "latency_p95_us": row.latency_p95_us,
                "retries_total": row.retries_total,
                "concurrent_sessions": row.concurrent_sessions,
                "observed_bandwidth_bps": row.observed_bandwidth_bps,
                "test_duration_s": row.test_duration_s,
                "pcap_bytes": row.pcap_bytes,
                "pcap_packets": row.pcap_packets,
                "cache_recommendation": row.cache_recommendation,
                "artifact_dir": str(row.case_dir),
                "scenario_file": str(row.scenario_file),
                "command": row.command,
                "warnings": row.warnings,
                "error": row.error,
            }
            for row in results
        ],
        "regressions_within_campaign": regressions_within,
        "regressions_vs_baseline": regressions_baseline,
        "blocked_cases": blocked_cases,
    }
    write_text(out_dir / "report_campaign.json", json.dumps(payload, indent=2) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Run multi-KPI performance suite with x2 scaling and regression checks."
    )
    ap.add_argument("--repo-root", default=".", help="Repository root (default: cwd).")
    ap.add_argument("--out-dir", default="", help="Output root directory.")
    ap.add_argument("--factors", default="1,2,4,8", help="Comma-separated scaling factors.")
    ap.add_argument("--extreme-factor", type=int, default=0, help="Optional extra overload factor (for example 10).")
    ap.add_argument("--kpis", default=",".join(SUPPORTED_KPIS), help="Comma-separated KPI list.")
    ap.add_argument("--base-terminals", type=int, default=20, help="Base terminal count per test.")
    ap.add_argument("--sessions-per-terminal", type=int, default=50, help="Base sessions/s per terminal for CPS seed.")
    ap.add_argument(
        "--cps-per-client",
        type=int,
        default=0,
        help="Override CPS seed per client for CPS/session KPIs (for example 500000).",
    )
    ap.add_argument(
        "--mbps-per-client",
        type=float,
        default=0.0,
        help="Override target Mbps per client for bandwidth KPIs (for example 1.0).",
    )
    ap.add_argument("--workers", type=int, default=4, help="Worker count.")
    ap.add_argument("--iterations", type=int, default=4, help="Campaign dichotomy iterations.")
    ap.add_argument("--step-s", type=float, default=0.1, help="Runtime step.")
    ap.add_argument("--run-window-general", default="15m", help="Run window for bandwidth-oriented KPIs.")
    ap.add_argument("--run-window-cps", default="30m", help="Run window for CPS/sessions KPIs.")
    ap.add_argument("--p-cores", type=int, default=2, help="P cores for efficiency normalization.")
    ap.add_argument("--e-cores", type=int, default=2, help="E cores for efficiency normalization.")
    ap.add_argument("--tcp-payload-bytes", type=int, default=10240, help="Payload size used in max_bandwidth_tcp scenario.")
    ap.add_argument("--udp-payload-bytes", type=int, default=10240, help="Payload size used in max_bandwidth_udp scenario.")
    ap.add_argument("--cpe-base", type=int, default=1, help="Base number of CPE/Livebox instances in each scenario.")
    ap.add_argument("--cpe-scale-with-factor", action="store_true", help="Scale CPE count with factor (cpe_base * factor).")
    ap.add_argument("--udp-ttl-s", type=int, default=900, help="UDP session TTL in seconds for max_bandwidth_udp.")
    ap.add_argument("--udp-unidirectional", action="store_true", help="Disable UDP full duplex mode (default is bidirectional).")
    ap.add_argument("--pcap-iface", default="", help="Interface used for per-campaign pcap capture.")
    ap.add_argument("--pcap-bytes", type=int, default=102400, help="Pcap budget in bytes per campaign.")
    ap.add_argument("--no-pcap", action="store_true", help="Disable per-campaign pcap capture.")
    ap.add_argument("--seed-cps-cap", type=int, default=100_000_000, help="Safety cap for generated seed CPS.")
    ap.add_argument("--regression-threshold", type=float, default=0.15, help="Regression threshold for KPI drops.")
    ap.add_argument("--baseline-report", default="", help="Optional path to previous report_campaign.json.")
    ap.add_argument("--no-perf", action="store_true", help="Disable perf counters capture in campaign-cache wrapper.")
    args = ap.parse_args()

    repo = Path(args.repo_root).resolve()
    out_dir = Path(args.out_dir).resolve() if args.out_dir else (
        Path("/tmp") / f"vmoongen-perf-suite-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    scenarios_dir = out_dir / "scenarios"
    campaigns_dir = out_dir / "campaigns"
    scenarios_dir.mkdir(parents=True, exist_ok=True)
    campaigns_dir.mkdir(parents=True, exist_ok=True)

    factors = parse_factors(args.factors)
    if args.extreme_factor and args.extreme_factor > 0 and args.extreme_factor not in factors:
        factors.append(args.extreme_factor)
        factors.sort()
    kpis = parse_kpis(args.kpis)

    ctl = repo / "scripts" / "vmoongenctl"
    if not ctl.exists():
        raise FileNotFoundError(f"missing CLI: {ctl}")

    case_results: List[CaseResult] = []
    blocked_cases: List[str] = []

    prev_best_cps_by_factor: Dict[int, float] = {}

    for factor in factors:
        terminals = max(1, args.base_terminals * factor)
        for kpi in kpis:
            prev_best = prev_best_cps_by_factor.get(factor)
            seed_cps = kpi_seed_cps(
                kpi=kpi,
                terminals=terminals,
                sessions_per_terminal=args.sessions_per_terminal,
                prev_cps_best=prev_best,
                cps_per_client_override=(args.cps_per_client if args.cps_per_client > 0 else None),
                mbps_per_client_override=(args.mbps_per_client if args.mbps_per_client > 0 else None),
                tcp_payload_bytes=args.tcp_payload_bytes,
                udp_payload_bytes=args.udp_payload_bytes,
                seed_cps_cap=args.seed_cps_cap,
            )
            cpe_count = max(1, int(args.cpe_base))
            if args.cpe_scale_with_factor:
                cpe_count = max(1, cpe_count * factor)
            cpe_count = min(cpe_count, terminals)
            ue_per_cpe = max(1, int(math.ceil(float(terminals) / float(cpe_count))))
            scenario_id = f"{kpi}_x{factor}_t{terminals}"
            scenario_file = scenarios_dir / f"{scenario_id}.lua"
            scenario_file.write_text(
                scenario_lua(
                    scenario_id=scenario_id,
                    terminals=terminals,
                    seed_cps=seed_cps,
                    kpi=kpi,
                    tcp_payload_bytes=args.tcp_payload_bytes,
                    udp_payload_bytes=args.udp_payload_bytes,
                    cpe_count=cpe_count,
                    ue_per_cpe=ue_per_cpe,
                    udp_ttl_s=max(1, int(args.udp_ttl_s)),
                    udp_bidirectional=(not args.udp_unidirectional),
                ),
                encoding="utf-8",
            )

            case_dir = campaigns_dir / kpi / f"x{factor}"
            case_dir.mkdir(parents=True, exist_ok=True)
            run_window = window_for_kpi(kpi, args.run_window_general, args.run_window_cps)

            cmd = [
                str(ctl),
                "scenario-campaign-cache",
                str(scenario_file),
                "--workers",
                str(args.workers),
                "--iterations",
                str(args.iterations),
                "--step-s",
                str(args.step_s),
                "--run-window",
                run_window,
                "--out-dir",
                str(case_dir),
                "--p-cores",
                str(args.p_cores),
                "--e-cores",
                str(args.e_cores),
            ]
            if args.no_perf:
                cmd.append("--no-perf")
            if args.no_pcap:
                cmd.append("--no-pcap")
            else:
                cmd.extend(["--pcap-bytes", str(max(24, int(args.pcap_bytes)))])
                if args.pcap_iface:
                    cmd.extend(["--pcap-iface", args.pcap_iface])

            status = "ok"
            error = None
            warnings: List[str] = []
            try:
                proc = run_cmd(cmd, cwd=repo)
                write_text(case_dir / "case-run.log", proc.stdout)
                if proc.stderr:
                    write_text(case_dir / "case-stderr.log", proc.stderr)
            except subprocess.CalledProcessError as exc:
                status = "error"
                error = f"exit={exc.returncode}"
                write_text(case_dir / "case-run.log", exc.stdout or "")
                write_text(case_dir / "case-stderr.log", exc.stderr or "")
                blocked_cases.append(
                    f"{kpi} factor x{factor} failed (exit {exc.returncode}); see {case_dir}"
                )

            best_cps = 0.0
            observed_cps = 0.0
            drop_rate = 1.0
            latency = 0.0
            retries = 0.0
            concurrent = 0.0
            observed_bw = 0.0
            test_duration_s = float(parse_duration_seconds(run_window))
            efficiency: Dict[str, Any] = {}
            cache_reco = ""

            if status == "ok":
                try:
                    (
                        best_cps,
                        observed_cps,
                        drop_rate,
                        latency,
                        retries,
                        concurrent,
                        observed_bw,
                        test_duration_s,
                    ) = parse_case_metrics(case_dir)
                except Exception as exc:
                    status = "error"
                    error = f"metrics parse error: {exc}"
                    blocked_cases.append(f"{kpi} factor x{factor} metrics parse failed: {exc}")

            if status == "ok":
                eff_path = case_dir / "cache-efficiency.json"
                if eff_path.exists():
                    try:
                        efficiency = load_json(eff_path)
                        cache_reco = str(
                            ((efficiency.get("cache_capacity_model") or {}).get("recommendation") or "")
                        )
                        observed_bw = float(
                            (efficiency.get("kpi") or {}).get("p1_observed_bandwidth_bps") or observed_bw
                        )
                        if ((efficiency.get("kpi") or {}).get("cache_utilization_pct") or {}).get(
                            "l1_hit_rate_pct"
                        ) is None:
                            warnings.append("perf counters unavailable: cache hit/miss is null")
                    except Exception as exc:
                        warnings.append(f"efficiency parse warning: {exc}")
                else:
                    warnings.append("missing cache-efficiency.json")

                pcap_bytes, pcap_packets = parse_pcap_summary(case_dir)
                if (not args.no_pcap) and (pcap_bytes <= 24 or pcap_packets <= 0):
                    warnings.append(
                        "pcap capture is empty: no packet observed on selected interface during this case"
                    )
            else:
                pcap_bytes, pcap_packets = 0, 0

            case_result = CaseResult(
                status=status,
                kpi=kpi,
                factor=factor,
                terminals=terminals,
                seed_cps=seed_cps,
                run_window=run_window,
                case_dir=case_dir,
                scenario_file=scenario_file,
                command=cmd,
                best_cps=best_cps,
                observed_cps=observed_cps,
                drop_rate=drop_rate,
                latency_p95_us=latency,
                retries_total=retries,
                concurrent_sessions=concurrent,
                observed_bandwidth_bps=observed_bw,
                test_duration_s=test_duration_s,
                pcap_bytes=pcap_bytes,
                pcap_packets=pcap_packets,
                efficiency=efficiency,
                cache_recommendation=cache_reco,
                warnings=warnings,
                error=error,
            )
            case_results.append(case_result)

            if status == "ok" and kpi == "max_cps_tcp":
                prev_best_cps_by_factor[factor] = best_cps

    regressions_within = regression_checks_within_campaign(case_results, args.regression_threshold)
    baseline_path = Path(args.baseline_report).resolve() if args.baseline_report else None
    regressions_baseline, baseline_payload = regression_checks_against_baseline(
        case_results, baseline_path, args.regression_threshold
    )

    config: Dict[str, Any] = {
        "factors": factors,
        "kpis": kpis,
        "base_terminals": args.base_terminals,
        "sessions_per_terminal": args.sessions_per_terminal,
        "cps_per_client": args.cps_per_client,
        "mbps_per_client": args.mbps_per_client,
        "workers": args.workers,
        "iterations": args.iterations,
        "step_s": args.step_s,
        "run_window_general": args.run_window_general,
        "run_window_cps": args.run_window_cps,
        "p_cores": args.p_cores,
        "e_cores": args.e_cores,
        "tcp_payload_bytes": args.tcp_payload_bytes,
        "udp_payload_bytes": args.udp_payload_bytes,
        "cpe_base": args.cpe_base,
        "cpe_scale_with_factor": bool(args.cpe_scale_with_factor),
        "udp_ttl_s": args.udp_ttl_s,
        "udp_bidirectional": (not args.udp_unidirectional),
        "pcap_iface": args.pcap_iface,
        "pcap_bytes": args.pcap_bytes,
        "pcap_enabled": (not args.no_pcap),
        "seed_cps_cap": args.seed_cps_cap,
        "regression_threshold": args.regression_threshold,
        "baseline_report": str(baseline_path) if baseline_path else "",
        "no_perf": bool(args.no_perf),
    }
    build_report(
        out_dir=out_dir,
        results=case_results,
        regressions_within=regressions_within,
        regressions_baseline=regressions_baseline,
        config=config,
        blocked_cases=blocked_cases,
        baseline_payload=baseline_payload,
    )

    print(str(out_dir / "report_campaign.txt"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
