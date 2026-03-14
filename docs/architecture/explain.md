Why profiles instead of per-flow Lua

A million-session system cannot afford chatty control-plane calls like:
	•	connect one session
	•	send one payload
	•	close one session

Instead, Lua should define profiles such as:
	•	client IP range
	•	server list
	•	ports
	•	CPS
	•	duration
	•	payload template
	•	close mode
	•	optional timing model

The runtime then installs and executes the profile in batch.

Worker sharding

Sessions must be partitioned across workers.

Example:
worker0 -> shard0
worker1 -> shard1
worker2 -> shard2
worker3 -> shard3

Each worker owns:
	•	its session subset
	•	its counters
	•	its timers

Avoid:
	•	cross-worker session mutation
	•	global shared flow tables
	•	default per-flow stats export

Profile model

A profile represents a synthetic workload.

Example fields:
	•	name
	•	protocol
	•	client subnet or pool
	•	server endpoints
	•	cps
	•	duration_s
	•	payload template
	•	close_mode
	•	stats interval

Example:

vpp.install_profile({
  name = "http_million",
  protocol = "tcp",
  clients = "10.0.0.0/16",
  servers = {
    { ip = "192.0.2.10", port = 80 }
  },
  cps = 50000,
  duration_s = 60,
  payload = "GET / HTTP/1.1\r\nHost: test\r\n\r\n",
  close_mode = "graceful",
  stats_interval_ms = 1000
})

Session lifecycle

A profile-driven session lifecycle is:
	1.	install profile
	2.	compile and shard plan
	3.	start profile
	4.	VPP ramps session creation at target CPS
	5.	VPP owns session execution
	6.	MoonGen polls aggregate stats
	7.	stop or drain profile
	8.	collect summary

Observability model

Default stats should be aggregate-only:
	•	active_sessions
	•	sessions_started
	•	sessions_closed
	•	connection_failures
	•	tx_bytes
	•	rx_bytes
	•	tx_packets
	•	rx_packets
	•	worker_count
	•	cps_current

Per-flow observability should be sampling-based or explicitly enabled.

Roadmap

Phase 1
	•	define profile-driven Lua API
	•	keep mock bridge
	•	return aggregate mock stats

Phase 2
	•	add real adapter schema
	•	connect adapter to real VPP control path

Phase 3
	•	install/start/stop real profiles
	•	add worker-sharded stats

Phase 4
	•	optimize scale path
	•	add sampled session tracing
	•	optionally replace bridge with native binding

Backend model

The VPP backend is profile-driven.

The preferred control model is:
	•	install_profile
	•	start_profile
	•	get_profile_stats
	•	stop_profile
	•	remove_profile

Not:
	•	per-flow connect/send/close loops from Lua

Responsibilities

MoonGen
	•	validate profile input
	•	compile plan inputs
	•	invoke adapter commands
	•	display profile state and stats

Adapter
	•	serialize profile definitions
	•	provide stable control verbs
	•	convert backend responses into MoonGen-friendly values

VPP
	•	execute session workloads
	•	own worker-local session state
	•	own TCP and timers
	•	export counters

Control verbs

The adapter interface should revolve around these verbs:
	•	connect
	•	disconnect
	•	install_profile
	•	start_profile
	•	stop_profile
	•	remove_profile
	•	get_profile_stats
	•	list_profiles

Non-goals

The adapter is not:
	•	a TCP stack
	•	a packet generator
	•	a per-packet scripting surface

Observability

Default observability is aggregated:
	•	per-profile
	•	per-worker
	•	process-level health

Per-session detail is optional and sampled.
