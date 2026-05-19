# NemoClaw Multi-Agent Pipelines — Cheatsheet

```
┌──────────────────────── NemoClaw ─────────────────────────┐
│  ┌────────────────── OpenShell sandbox ─────────────────┐ │
│  │  Landlock · seccomp · OPA + proxy · Privacy Router   │ │
│  │                                                       │ │
│  │   ┌─────────────── OpenClaw gateway ───────────────┐ │ │
│  │   │                                                 │ │ │
│  │   │   supervisor ──► sessions_spawn ──► researcher │ │ │
│  │   │       ▲                              │         │ │ │
│  │   │       │                              ▼         │ │ │
│  │   │   reviewer  ◄────────  coder  ◄─ STATE.yaml    │ │ │
│  │   │                                                 │ │ │
│  │   └─────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

## Three orchestration patterns — pick one

| Pattern | When to reach for it | Hand-off |
|---|---|---|
| **Orchestrator (CEO)** | Linear pipeline, one driver | `sessions_spawn` |
| **Peer-to-Peer** | Parallel work, no central reasoner | Shared `STATE.yaml` |
| **Shared Memory** | Queryable cross-agent context | `memorySearch` collections |

`Stop` hooks layer on top of any of these for event-driven hand-off.

## The 6 commands you'll actually run

1. `nemoclaw onboard` — one-time wizard; bakes the blueprint, picks inference provider.
2. `openclaw agents add --workspace ~/.openclaw/workspace-<name> <name>` — declare an agent.
3. `nemoclaw start --config openclaw.json` — boot the sandbox; provisions all `workspace-*/`.
4. `nemoclaw open <agent>` — interactive session with a named agent.
5. `openshell term` — TUI for approving / denying policy violations.
6. `nemoclaw snapshot create|restore <name>` — round-trip the entire pipeline state.

## Key paths

| Path | What's there |
|---|---|
| `~/.openclaw/agents/<id>/` | Per-agent state directory on the host |
| `/sandbox/.openclaw/workspace-<name>/` | Per-agent workspace inside the sandbox |
| `<workspace>/SOUL.md` | One agent's persona / role / boundaries |
| `openclaw.json` | Agent roster + channel bindings |

## Security at a glance

| Layer | Mechanism | Blocks |
|---|---|---|
| Filesystem | Landlock LSM | Writes outside `/sandbox`, `/tmp` |
| Process | seccomp BPF | `ptrace`, `mount`, kernel-dangerous syscalls |
| Network | OPA + HTTP proxy in netns | All egress; opens via YAML allowlists |
| Inference | Privacy Router | API-key exfiltration; keys are host-side |

Filesystem & process policy locks at boot. **Inference routing hot-reloads.**

## Where to go next

- NeMo Agent Toolkit — github.com/NVIDIA/NeMo-Agent-Toolkit
- ClawHub — community skill registry (treat third-party skills like third-party packages)
- ACP standard (JetBrains/Zed) — agentclientprotocol.com
- Issue #1260 — what's still rough (shared mount, `workspaces list`, skill propagation)
