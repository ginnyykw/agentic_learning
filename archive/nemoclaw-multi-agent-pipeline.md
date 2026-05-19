# Pipelining Independent Agents in NemoClaw

A guide to spawning several named agents in the same sandbox, giving each a distinct job, and having them hand work off to each other — using NemoClaw's native primitives.

> Reference point: *"I built a multi-agent system on NVIDIA NemoClaw — then my Brev credits ran out"* (Lakshmi Narayana U., Medium). The article is heavy on narrative and light on wiring; this document is the wiring.

---

## 1. Two products, one runtime

Before any commands, separate two things the marketing tends to merge:

| Layer | What it is | Where it lives |
|---|---|---|
| **OpenClaw** | The cognitive framework — agents, sessions, skills, gateway/bindings to messaging channels. TypeScript/Node.js. | The "brains." Runs as a daemon. |
| **NemoClaw** | NVIDIA's hardened distribution: OpenClaw + the **OpenShell** sandbox runtime. | The "container." Wraps and isolates everything OpenClaw does. |
| **OpenShell** | The security/policy layer inside NemoClaw. Landlock, seccomp, OPA, namespaces. | The "walls." |

You write OpenClaw config (`openclaw.json`, `SOUL.md`, skills). NemoClaw runs it inside OpenShell. The pipeline patterns below are OpenClaw concepts; the security guarantees in §7.5 are OpenShell concepts.

---

## 2. The one feature that makes a pipeline possible

Per docs PR #2383 (merged into `v0.0.24`, closing issue #1260), the sandbox can host **multiple named agents simultaneously**, each with its own workspace:

```
/sandbox/.openclaw/workspace-<name>/   →   /sandbox/.openclaw-data/workspace-<name>/
```

Two facts drive every design choice below:

1. **Each named agent's workspace is symlink-backed by `.openclaw-data/`**, so its files survive sandbox restarts. `provision_agent_workspaces` runs at boot and recreates the symlinks.
2. **Per-agent files do not sync across workspaces.** Anything one agent writes inside its `workspace-<name>/` is invisible to the others. This is the most important fact in the guide; every "how do they communicate" answer below is downstream of it.

Issue #1260 explicitly tracks the missing pieces (shared mount, `nemoclaw workspaces list`, multi-workspace backup script), so know that you're building on a feature that's still maturing.

---

## 3. Pick your pipeline shape first

Four shapes work cleanly inside NemoClaw. Pick one before you write any config.

| Shape | When to use | Hand-off mechanism |
|---|---|---|
| **Orchestrator (CEO)** | One driver agent decomposes a task and dispatches | Supervisor calls `sessions_spawn` and reads workers' return messages |
| **Peer-to-Peer** | Multi-step pipeline; agents work autonomously, no central reasoner | A shared `STATE.yaml` that all agents poll and update |
| **Shared Memory** | Cross-agent context that needs to be queryable, not file-shaped | `memorySearch` collections written by one agent, retrieved by another |
| **Event-driven** | "When agent A finishes, agent B should react" | `Stop` hooks layered over any of the three above |

The Medium article's pattern is Orchestrator (CEO). The rest of this guide uses that as the worked example, then shows how to retrofit the others onto the same setup.

---

## 4. Declare the agents

Edit `openclaw.json` with named agents and (optionally) channel bindings:

```json
{
  "agents": [
    {
      "name": "supervisor",
      "model": "nvidia/llama-3.3-nemotron-super-49b",
      "workspace": "~/.openclaw/workspace-supervisor"
    },
    {
      "name": "researcher",
      "model": "nvidia/llama-3.3-nemotron-super-49b",
      "workspace": "~/.openclaw/workspace-researcher"
    },
    {
      "name": "coder",
      "model": "nvidia/nemotron-3-nano-30b-a3b",
      "workspace": "~/.openclaw/workspace-coder"
    },
    {
      "name": "reviewer",
      "model": "nvidia/llama-3.3-nemotron-super-49b",
      "workspace": "~/.openclaw/workspace-reviewer"
    }
  ],
  "bindings": [
    { "match": { "channel": "telegram", "chat": "ops-team" }, "agent": "supervisor" },
    { "match": { "channel": "slack",    "user":  "*"        }, "agent": "supervisor" }
  ]
}
```

Bindings are deterministic, most-specific-match-wins routing rules. Inbound messages from a connected channel land at the matching agent. For a back-end pipeline you can omit them entirely; you'll talk to agents over the CLI.

You can also add agents one at a time:

```bash
openclaw agents add --workspace ~/.openclaw/workspace-researcher researcher
```

Boot the sandbox and confirm the workspaces materialized:

```bash
nemoclaw start --config openclaw.json
openshell sandbox exec -- ls -d /sandbox/.openclaw/workspace-*
```

Expect `workspace-supervisor`, `workspace-researcher`, `workspace-coder`, `workspace-reviewer`.

---

## 5. Define each agent's role with `SOUL.md`

Every OpenClaw agent's persona lives in **`SOUL.md`** in its workspace. Distinct from `AGENTS.md` (which is the project-wide agent index — what's available, not who any one of them is).

Drop the coder's `SOUL.md` in:

```bash
openshell sandbox exec -- bash -c 'cat > /sandbox/.openclaw/workspace-coder/SOUL.md' <<'MD'
# Coder Agent

You are the **coder** in a four-agent pipeline.

## Your job
- Read the brief at `/sandbox/shared/handoff/brief.md` (the researcher dropped it there).
- Implement the requested change in the target repo.
- Write your patch summary to `/sandbox/shared/handoff/patch.md`.
- Stop. Do not review your own work — that's the reviewer's job.

## Out of scope
- Web research (researcher's job).
- Test writing (reviewer's job — but include a *plan* for tests in your summary).

## Tools you should prefer
- `git apply` over manual edits when you have a patch.
- The `code-search` skill before grepping by hand.
MD
```

Repeat per agent. Supervisor's `SOUL.md` describes the dispatch logic; workers' describe their narrow task and exactly one input path + one output path. **Tight role boundaries are what make a pipeline a pipeline instead of four agents fighting over the same file.**

---

## 6. Solve the communication problem

Since per-agent workspaces don't sync, you need a coordination layer. Four documented patterns; pick the one that fits the work.

### 6a. Orchestrator (CEO) via `sessions_spawn`

The supervisor doesn't write to the filesystem — it calls workers as sub-agents and reads their return messages directly. From the supervisor's session:

```
> sessions_spawn researcher "Find current best practice for input validation in <stack>."
> sessions_spawn coder    "Apply the brief above; return a patch."
> sessions_spawn reviewer "Review the patch; write tests; return pass/fail."
```

Each spawn returns the worker's final message in-context. No files needed for hand-off. Single-rooted trace (one supervisor session, N children visible underneath). This is the closest fit to the Medium article's "orchestrator + specialists."

### 6b. Peer-to-Peer via `STATE.yaml`

When the supervisor's reasoning becomes the bottleneck (long-running stages, parallel work, multi-repo refactors), drop it. Instead, agents write to a shared state file outside any per-agent workspace and poll it for unblocked work:

```bash
openshell sandbox exec -- mkdir -p /sandbox/shared
openshell sandbox exec -- chmod 0777 /sandbox/shared
```

```yaml
# /sandbox/shared/STATE.yaml
task: "Add input validation to /api/users POST and write tests."
stages:
  research: { owner: researcher, status: done,    artifact: brief.md }
  code:    { owner: coder,      status: pending, depends_on: [research] }
  review:  { owner: reviewer,   status: pending, depends_on: [code] }
```

Each agent's `SOUL.md` says: "When my stage's `depends_on` are all `done`, take ownership and update my own status." No central coordinator.

> Caveat from PR #2383: shared-file propagation is currently *manual*. `/sandbox/shared/` works because it's not under `.openclaw/workspace-*/`, but a proper shared mount is tracked as a follow-up. Until then, the directory is accessible because nothing stops it — not because NemoClaw guarantees cross-workspace consistency.

### 6c. Shared Memory via `memorySearch`

For context that's queryable rather than file-shaped — "every API quirk the researcher has noticed," "every test the reviewer has written" — use a memory collection that one agent writes to and others retrieve from:

```
researcher → memorySearch.write("api-quirks", "<finding>")
coder      → memorySearch.read("api-quirks", query="user email validation")
```

Use this when the consumer doesn't know in advance which artifact it needs (so it queries) rather than when it's reading the next stage's output (use 6a/6b for that).

### 6d. `Stop`-hooks for event-driven hand-off

Layer over any of the above. When agent A finishes, fire a hook that nudges agent B:

```jsonc
// .openclaw/workspace-researcher/settings.json
{
  "hooks": {
    "Stop": [
      { "command": "nemoclaw send --to coder --message-file /sandbox/shared/brief.md" }
    ]
  }
}
```

Right shape for "researcher writes the brief, coder picks it up immediately, supervisor doesn't have to babysit." Easiest transition to debug in production because each one is a logged hook event.

---

## 7. Skills as the shared knowledge layer

Skills are the *one* thing you genuinely want shared across agents — domain knowledge, internal API patterns, the contract for `STATE.yaml`. Put them in the skills tree and let `scripts/docs-to-skills.py` (regenerated automatically by pre-commit per PR #2383) build them out:

```
docs/
  ├── api-conventions.md
  └── pipeline-state-format.md       # describes the STATE.yaml contract
.agents/skills/
  ├── api-conventions/SKILL.md
  └── pipeline-state-format/SKILL.md
```

Now every agent has access to `pipeline-state-format` and reads/writes `STATE.yaml` consistently.

ClawHub is the community skill registry — handy for stock integrations (Slack, Jira, GitHub) without rolling your own. Treat third-party skills the same way you'd treat third-party npm packages: read the source before you trust it.

> The PR is explicit that skills do not propagate automatically into per-agent workspaces today. `scripts/docs-to-skills.py` regenerates the canonical `.agents/skills/` tree, but pushing those into each `workspace-<name>/` is still on the manual list under issue #1260. Materialize them at boot in your provisioning script if you can't wait for the shared-mount work.

---

## 7.5 The OpenShell security model

The runtime guarantees the agents can't violate. Worth a slide in any talk because this is what makes "let an autonomous agent run" something a security review will sign off on.

| Layer | Mechanism | What it blocks |
|---|---|---|
| **Filesystem** | Landlock LSM | Writes outside `/sandbox` and `/tmp`; the host system is read-only to the agent |
| **Process** | seccomp BPF | Dangerous syscalls (`ptrace`, `mount`, …) at the kernel level |
| **Network** | OPA + HTTP proxy in a network namespace | All egress is blocked by default; declarative YAML allowlists open specific destinations |
| **Inference** | Privacy Router | API keys are stripped from the agent and injected at the host boundary, so a compromised agent can't exfiltrate them |

Two operational consequences:

- **Filesystem and process policy is locked at sandbox creation.** You can't relax it without a restart.
- **Inference routing is hot-reloadable.** Switch a worker from local Ollama to a frontier API mid-run to handle a complexity spike, without touching identity or memory.

When an agent attempts an action outside the policy (calling an unlisted API, writing outside `/sandbox`), OpenShell blocks it and surfaces an approval prompt in the **`openshell term`** TUI. Operator approves or denies; every decision is audit-logged.

---

## 8. The supervisor's playbook

Encode the pipeline as an explicit recipe in the supervisor's `SOUL.md`:

```markdown
# Supervisor

You orchestrate four agents. Never do their work yourself.

## Recipe (Orchestrator pattern)
1. Write the user's request to `/sandbox/shared/STATE.yaml` under `task:`.
2. `sessions_spawn researcher` with input "Read STATE.yaml; produce brief.md."
3. When researcher returns, `sessions_spawn coder` with input
   "Read brief.md; produce patch.md."
4. When coder returns, `sessions_spawn reviewer` with input
   "Read patch.md; produce review.md."
5. Read review.md and present the final result to the user.

## Rules
- If any worker returns an error, stop and surface it. Do not retry blindly.
- Do not edit code. Do not run tests. Do not search the web. Delegate.
- If the user asks for a change mid-pipeline, restart from step 1 with the
  amended task; do not patch over a half-finished hand-off.
```

The whole pipeline is now: a recipe in markdown, four named agents, a shared state file, and one shared skill.

---

## 9. Snapshot the whole pipeline as one unit

PR #2383 extends `snapshot create` and `snapshot restore` to discover `workspace-*/` automatically. One command, all four workspaces:

```bash
nemoclaw snapshot create  pipeline-before-demo
# ...run a demo, things go sideways...
nemoclaw snapshot restore pipeline-before-demo
```

The manifest's `stateDirs` will list every per-agent workspace plus the default one. On older builds (pre-`v0.0.24`), use the discover-and-backup loop in §10.

---

## 10. Manual backup (older builds, or paranoia)

The pattern from the PR's `backup-restore.md`:

```bash
# Discover and download every per-agent workspace
openshell sandbox exec -- bash -c '
  for ws in /sandbox/.openclaw/workspace-*/; do
    name=$(basename "$ws")
    tar czf "/tmp/$name.tgz" -C "$ws" .
  done
'

# Pull tarballs out of the sandbox
for name in supervisor researcher coder reviewer; do
  openshell sandbox cp "/tmp/workspace-$name.tgz" "./backup/"
done
```

Restore is the inverse: copy tarballs back in, untar into the matching `workspace-<name>/`.

---

## 11. ACP bridge — connecting to your IDE

If you'd rather drive the pipeline from JetBrains or Zed than from a chat channel, OpenClaw ships an **ACP (Agent Client Protocol)** bridge over stdio. The bridge translates the IDE's NDJSON protocol to OpenClaw's WebSocket gateway, maps ACP session IDs to gateway session keys, and forwards token streams as `agent_message_chunk` notifications.

Limitations as of this writing: no client-side filesystem methods (the bridge can't read your local files for the agent), no terminal creation. Use it as a remote console to a gateway-managed pipeline, not as a replacement for IDE-native code-edit tools.

---

## 12. End-to-end smoke test

```bash
# 1. Boot the sandbox
nemoclaw start --config openclaw.json

# 2. Confirm workspaces are provisioned
openshell sandbox exec -- ls -la /sandbox/.openclaw/

# 3. Confirm shared state is reachable
openshell sandbox exec -- ls -la /sandbox/shared/

# 4. Open the supervisor and give it a task
nemoclaw open supervisor
> "Add input validation to /api/users POST and write tests."

# 5. Watch STATE.yaml evolve
openshell sandbox exec -- watch -n0.5 cat /sandbox/shared/STATE.yaml

# 6. Snapshot the result
nemoclaw snapshot create demo-run-1
```

Expect: stages flip `pending → in_progress → done` in order; the supervisor session prints the reviewer's final report.

---

## 13. Hermes as an alternative cognitive layer

If you want self-improving skills (the agent distills its own task trajectories into reusable `SKILL.md` files), the community **HermesClaw** integration runs Hermes Agent inside the same OpenShell sandbox. Trade-offs:

- **Gain**: reflective skill generation kicks in after ~5+ tool calls in a session, raising the capability ceiling without human authorship.
- **Lose**: Hermes is single-process with sub-agent spawning; you don't get OpenClaw's "multi-agent operating system" gateway feel.
- **Migration**: `hermes claw migrate` imports an existing OpenClaw `SOUL.md`, memories, and user skills, converting them into Hermes' `agentskills.io` format.

Run only one cognitive layer per sandbox at a time. The two share `sandbox-init.sh`; mixing them in the same sandbox is an integration project, not a config switch.

---

## 14. The honest list of rough edges

What the PR makes obvious is also what to plan around:

- **No shared mount yet.** `/sandbox/shared/` works because nothing stops it from working, not because NemoClaw promises cross-workspace consistency. Plan for that to change.
- **No `nemoclaw workspaces list`.** You're discovering workspaces with `ls /sandbox/.openclaw/workspace-*` until that lands.
- **Skills don't auto-propagate into per-agent workspaces.** Materialize at boot or fail early.
- **`chown -R sandbox:sandbox` exits 127 in the snapshot restore path** on at least some sandbox SSH sessions (caught during the PR's manual validation). Files come back fine because ownership was already correct, but if you script around restore, treat that exit code as non-fatal.

If any of those bite you, the issue to track is `#1260`.

> **Fact-check before going on stage**: the source document this guide drew from referenced "Nemotron-3 Super 120B," "13,000 ClawHub skills," a "LosslessClaw plugin for DAG hierarchical summarization," and "OpenClaw Search & Removal" tools by CrowdStrike. Verify these against current internal docs before quoting numbers or feature names from a slide — they read as the kind of specifics that drift between LLM-generated drafts.

---

## 15. What you actually have to write

- `openclaw.json` — agent declarations and (optional) channel bindings.
- One `SOUL.md` per agent workspace — narrow role, one input, one output.
- `docs/pipeline-state-format.md` — the contract for `STATE.yaml`. Auto-becomes a skill via `scripts/docs-to-skills.py`.
- Optional: `Stop` hooks in each `workspace-<name>/settings.json` to chain transitions.
- Optional: a tiny boot script that materializes shared skills into each `workspace-<name>/` until the shared-mount feature lands.

Everything else — `sessions_spawn`, sandbox isolation, persistence, snapshot/restore, OpenShell policy enforcement — is already in the box.
