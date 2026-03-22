# vMoonGen — Roadmap

_Dernière mise à jour : 2026-03-22_

vMoonGen est une plateforme de test réseau haute performance combinant MoonGen/LuaJIT,
VPP/fd.io, et un plan de management complet (DSL, DUT monitoring, TWAMP, AI/ML).

---

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────┐
│  MANAGEMENT PLANE   ██████████████████████░░  ~85% ✓           │
│  DSL · DUT · Bus · TWAMP · AI/ML · Campagne                    │
├─────────────────────────────────────────────────────────────────┤
│  CONTROL PLANE      ░░░░░░░░░░░░░░░░░░░░░░░░   0%              │
│  FRR/GoBGP · BGP · OSPF · IPSec reconvergence                  │
├─────────────────────────────────────────────────────────────────┤
│  DATA PLANE         ████████████░░░░░░░░░░░░  ~50% ✓           │
│  VPP/DPDK · DAC · TCP stack · Workers                          │
└─────────────────────────────────────────────────────────────────┘
```

### Politique de priorité

- **P0** — bloquant : aucune release sans ça
- **P1** — important : valeur réelle, peut attendre la stabilisation P0
- **P2** — long terme : recherche, optimisation, extensions

### Principe de validation

> Aucun milestone n'est considéré terminé tant que le test `2-arm` DAC traversal
> n'est pas vert sur le dataplane réel VPP/DPDK.

---

## Track 1 — Data Plane (VPP/DPDK)

### ✓ Fait

| Composant | État |
|-----------|------|
| VPP control-plane via CLI socket | ✓ validé |
| Persistent bridge daemon (UNIX socket) | ✓ validé |
| LuaJIT control client ↔ daemon | ✓ validé |
| DPDK binding des ports X710 (vfio-pci) | ✓ validé |
| Hugepages + IOMMU | ✓ validé |
| Topologie DAC cross-port identifiée | ✓ validé |
| Build VPP avec system DPDK (libdpdk.pc) | ✓ outillé |
| Container VPP build image | ✓ outillé |
| Render VPP session config (DPDK) | ✓ script |

### ○ Reste à faire

| Priorité | Tâche | Détail |
|----------|-------|--------|
| **P0** | **Câblage back-to-back deux MS-01** | SFP+ 10G de MS-01 #1 vers MS-01 #2 (DAC ou SFP+ cuivre) |
| **P0** | **VPP/DPDK forwarding réel** | Test CPS/sessions/drops — MS-01 #1 client, MS-01 #2 server |
| **P0** | **KPI capture end-to-end** | Collect métriques VPP sous charge sur les deux nœuds |
| **P0** | **Validation cross-machine** | Trafic réel traversant le lien physique inter-MS-01 |
| **P1** | **Capture pcap pendant les tests** | Capturer le trafic live sur une interface 10G (enp2s0f0np0 / enp2s0f1np1) pendant l'exécution d'un scénario ; fichier pcap horodaté, arrêt automatique en fin de test |
| **P1** | **Filtrage BPF sur capture live** | Appliquer un filtre BPF (syntaxe Wireshark/tcpdump) à la capture pour isoler des flux spécifiques ; option `--pcap-filter "host 10.0.1.1 and tcp"` |
| **P1** | **Stateful server behavior** | Vrai comportement serveur TCP (au-delà du skeleton déterministe) |
| **P1** | **Perf counters** (`perf stat`) | Cache hits/misses sur venus pendant les campagnes |
| **P2** | **1-arm mode** | Superflow client-only après validation 2-arm stable |
| **P2** | **SCTP path** | Descripteur de scénario + execution backend |
| **P2** | **25G / 100G NICs** | Intel E830-XXVDA2 (25G) → E810-CQDA1 (100G) |

---

## Track 2 — Management Plane (DSL + Orchestration)

### ✓ Fait

| Composant | Fichier | État |
|-----------|---------|------|
| Parser LPeg (grammaire complète) | `lua/vmg_parser.lua` | ✓ |
| Resolver (DUT, probe, agent) | `lua/vmg_resolver.lua` | ✓ |
| Runner (lifecycle pre/warmup/run/post) | `lua/vmg_runner.lua` | ✓ |
| Campaign runner (P0/P1/P2) | `lua/vmg_campaign_runner.lua` | ✓ |
| Profile loader | `lua/vmg_profile_loader.lua` | ✓ |
| DUT collector SSH + REST | `lua/vmg_dut_collector.lua` | ✓ |
| DUT parsers FortiGate 7.2/7.4 | `duts/parsers/fortigate.lua` | ✓ |
| DUT auto-détection vendor/firmware | `vmg_dut_collector.lua` | ✓ |
| Poller Python background | `tools/vmg_dut_poller.py` | ✓ |
| Event bus Redis Streams | `lua/vmg_event_bus.lua` | ✓ |
| Primitives DSL : `dut`, `agent`, `probe` | `vmg_parser.lua` | ✓ |
| Primitives DSL : `monitor`, `always_monitor` | `vmg_parser.lua` | ✓ |
| Primitives DSL : `pre`, `warmup`, `post` | `vmg_parser.lua` | ✓ |
| Profils inject/topology/probes/agents | `profiles/` | ✓ |

### ○ Reste à faire

| Priorité | Tâche | Détail |
|----------|-------|--------|
| **P0** | **Smoke test intégration** | Pipeline complet : parse → resolve → run → evaluate → bus |
| **P1** | **`pass_when` inline suite_test** | Évaluer les critères inline contre métriques agrégées (TODO dans runner) |
| **P1** | **Bisection ↔ runner** | Protocole complet `bisect_request` / `bisect_point` entre runner et agent |
| **P1** | **Poller Python → Redis** | `vmg_dut_poller.py` publie directement sur Redis Streams (NDJSON seulement aujourd'hui) |
| **P1** | **Profils DUT additionnels** | Cisco IOS-XE, Juniper JunOS, VPP DUT natif |
| **P2** | **Wizard DSL** | Génération de fichiers `.vmg` guidée (questions → DSL) |
| **P2** | **Import BreakingPoint** | Conversion topologies/profils Ixia BreakingPoint |
| **P2** | **Multi-node orchestration** | Plusieurs injecteurs coordonnés |

---

## Track 3 — AI / ML

### ✓ Fait

| Composant | Fichier | État |
|-----------|---------|------|
| AnomalyAgent (EWMA + Z-score) | `tools/vmg_ai_agent.py` | ✓ |
| BisectionAgent (recherche binaire CPS) | `tools/vmg_ai_agent.py` | ✓ |
| LogAgent (patterns regex logs DUT) | `tools/vmg_ai_agent.py` | ✓ |
| ModelScorer (IsolationForest/ZScore/ONNX) | `tools/vmg_ai_agent.py` | ✓ |
| Entraînement IsolationForest pur Python | `tools/vmg_model_trainer.py` | ✓ |
| Entraînement ZScoreBaseline | `tools/vmg_model_trainer.py` | ✓ |
| Export ONNX (sklearn + skl2onnx) | `tools/vmg_model_trainer.py` | ✓ |
| TWAMP server (MOS, jitter, OoO, DSCP) | `tools/vmg_twamp_server.py` | ✓ |
| TWAMP chain multi-segment | `vmg_twamp_server.py` | ✓ |
| Profils agents (anomaly/bisection/ipsec) | `profiles/agents/standard.lua` | ✓ |
| Profils probes TWAMP | `profiles/probes/twamp.lua` | ✓ |

### ○ Reste à faire

| Priorité | Tâche | Détail |
|----------|-------|--------|
| **P0** | **TWAMP reflector VPP** | Nœud VPP qui echo les paquets TWAMP en fast-path |
| **P1** | **RRCF streaming** | Robust Random Cut Forest — streaming, détecte anomalies ponctuelles ET changements de régime |
| **P1** | **LSTM ONNX** | Entraîner un LSTM court (16-32 unités, PyTorch → ONNX, ~5ms CPU) sur séries lab |
| **P1** | **`onnxruntime` intégration complète** | Tester le backend ONNX avec un vrai modèle sklearn exporté |
| **P1** | **Agent `report`** | Agrégation finale de campagne, génération rapport JSON/HTML |
| **P2** | **SLM config analysis** | Qwen2.5-0.5B ou phi-3.5-mini via llama.cpp — analyse config DUT sur anomalie |
| **P2** | **Fine-tuning lab** | Ré-entraîner sur données réelles après ~10 campagnes (labels pass/fail) |
| **P2** | **NPU edge** | Inférence sur RK3588 / Hailo-8 PCIe / SpacemiT K1 (RISC-V+AI) |
| **P2** | **ZML** | Hook `accelerator = "zml"` — zero-copy DPDK → tensor, framework trop jeune aujourd'hui |

---

## Track 4 — Control Plane

### ✓ Fait

_(rien — pas encore démarré)_

### ○ Reste à faire

| Priorité | Tâche | Détail |
|----------|-------|--------|
| **P2** | **FRR/GoBGP** | Interfaçage DUT via BGP, OSPF |
| **P2** | **Simulation événements réseau** | Bascule BGP, remontée tunnels IPSec, reconvergence |
| **P2** | **IPSec tunnel management** | Intégration cycle de vie IKE/IPSec dans les scénarios |

---

## Track 5 — Documentation et qualité

### ✓ Fait

| Document | État |
|----------|------|
| `doc/architecture.md` | ✓ mis à jour |
| `doc/management-plane.md` | ✓ nouveau |
| `doc/ai-sidecar.md` | ✓ mis à jour |
| `doc/vpp-integration.md` | ✓ |
| `doc/lua-dsl-v1.md` | ✓ |
| `doc/hardware-strategy.md` | ✓ |
| Mémoires persistantes (DSL, vision, composants) | ✓ |

### ○ Reste à faire

| Priorité | Tâche | Détail |
|----------|-------|--------|
| **P1** | **Guide de démarrage rapide** | De zéro à premier test en 15 minutes |
| **P1** | **Référence CLI complète** | Tous les scripts, arguments, variables d'environnement |
| **P1** | **Guide DUT** | Ajouter un nouveau vendor/firmware/transport |
| **P2** | **Guide AI/ML** | De la collecte de données à l'agent en production |

---

## Tableau de bord (2026-03-22)

| Track | Avancement | Bloquant |
|-------|-----------|----------|
| Data plane | ~50% | DAC physique + forwarding réel |
| Management plane | ~85% | Smoke test intégration |
| AI / ML | ~70% | TWAMP reflector VPP |
| Control plane | 0% | Non démarré (P2) |
| Documentation | ~80% | Guides pratiques manquants |
| **Global** | **~60%** | **DAC réel + smoke test** |

---

## Prochaines étapes immédiates (P0)

1. **Câbler les deux MS-01 en back-to-back** — port SFP+ 10G de MS-01 #1 vers port SFP+ 10G de MS-01 #2 (DAC ou SFP+ cuivre)
2. **Premier test `2-arm` sur dataplane réel** — CPS, drops, latence sous charge (MS-01 #1 = client, MS-01 #2 = server)
3. **Smoke test intégration management plane** — parse → run → evaluate → bus events
4. **TWAMP reflector** — nœud VPP minimal sur MS-01 #1, analyzer sur MS-01 #2

Ces quatre points débloquent l'essentiel du reste.

---

## Références

- [architecture.md](architecture.md) — Architecture trois plans
- [management-plane.md](management-plane.md) — Plan de management complet
- [vpp-integration.md](vpp-integration.md) — Intégration VPP/DPDK
- [lua-dsl-v1.md](lua-dsl-v1.md) — DSL Lua v1
- [ai-sidecar.md](ai-sidecar.md) — AI sidecar et détection temps réel
- [hardware-strategy.md](hardware-strategy.md) — NICs, NPU, stratégie matérielle
