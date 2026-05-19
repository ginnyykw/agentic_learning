# Demo Script — NemoClaw Multi-Agent Pipeline

A 9-beat live demo. Each beat: spoken intro, command, expected output, fallback.

> **Total runtime target**: 12–15 minutes including the recap. Cut Beat 7 (hot-reload inference) first if you're tight.

---

## Pre-demo checklist (do all of this *before* you walk on stage)

1. **GPU host ready.** Brev instance up, or local DGX/RTX box reachable.
   ```bash
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```
2. **NemoClaw installed.**
   ```bash
   curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
   nemoclaw onboard         # interactive wizard, run once
   ```
3. **Models pre-pulled.** This is the single biggest source of stage embarrassment — a "cold start" while the audience watches.
   ```bash
   ollama pull <reasoning-model>
   ollama pull <coder-model>
   ```
4. **`openclaw.json` and four `SOUL.md` files present in their workspaces.** Verify with `openshell sandbox exec -- ls -d /sandbox/.openclaw/workspace-*`.
5. **Baseline snapshot taken.**
   ```bash
   nemoclaw snapshot create demo-baseline
   ```
6. **Two terminals on the projector.** Left: supervisor session. Right: a `watch` on `STATE.yaml`. Get the layout right before the audience is in the room.
7. **Network: have a wired backup.** Conference Wi-Fi is the second biggest source of stage embarrassment.

---

## Live beats

### Beat 1 — "Here's the sandbox."
*Frame the security story before the agents do anything visible.*

**Command:**
```bash
openshell sandbox info
```

**Expected output (key lines):**
```
landlock:    active (writable: /sandbox, /tmp)
seccomp:     loaded  (profile: nemoclaw-default)
namespace:   network=isolated  egress=blocked
inference:   ollama@127.0.0.1  (Privacy Router: enabled)
```

**Fallback:** If `sandbox info` errors, cut to a screenshot slide. Don't troubleshoot live.

**Talk track (~30s):** "Before any agent runs a single token, the runtime has already decided what it can and can't do. Filesystem, syscalls, network — all locked. The agent doesn't know the rules; the kernel enforces them."

---

### Beat 2 — "Four agents, one config."

**Show on screen:** `openclaw.json`, the `agents:` array. Talk through the four roles in one sentence each.

**Command:**
```bash
nemoclaw start --config openclaw.json
openshell sandbox exec -- ls -d /sandbox/.openclaw/workspace-*
```

**Expected output:**
```
/sandbox/.openclaw/workspace-supervisor
/sandbox/.openclaw/workspace-researcher
/sandbox/.openclaw/workspace-coder
/sandbox/.openclaw/workspace-reviewer
```

**Fallback:** If `nemoclaw start` is slow, the snapshot was probably stale — restore baseline (`nemoclaw snapshot restore demo-baseline`) and retry once.

**Talk track:** "Four agents, four isolated workspaces, one config file. Each workspace is symlink-backed, so this state survives a restart."

---

### Beat 3 — "Each one has its own brain."

**Show on screen:** Open `workspace-researcher/SOUL.md` and `workspace-coder/SOUL.md` side-by-side in your editor.

**No live command** — this is a slide-style pause. The point is visual contrast: the researcher's `SOUL.md` is one paragraph about briefs, the coder's is one paragraph about patches. Tight, narrow, non-overlapping.

**Talk track (~45s):** "If you only take one thing away from this demo: the agents don't share a soul. Each one has a single job described in one file. That's what keeps them from fighting over the same problem."

---

### Beat 4 — "Ask the supervisor."

**Command:**
```bash
nemoclaw open supervisor
```

In the supervisor's prompt:
```
Add input validation to /api/users POST and write tests.
```

**Expected output:** Supervisor begins planning. You should see the start of a `sessions_spawn researcher …` call within ~5 seconds.

**Fallback:** If the supervisor stalls, type "Plan first, then dispatch." as a nudge. If it still stalls, snapshot-restore and retry.

**Talk track (~30s):** "Notice the supervisor doesn't write code. It plans, dispatches, assembles. That's it."

---

### Beat 5 — "Watch the hand-off."

**Switch the audience's eye to the right-hand terminal.** This should already be running:

```bash
openshell sandbox exec -- watch -n0.5 cat /sandbox/shared/STATE.yaml
```

**Expected sequence (over ~2–3 minutes):**
```
research:  pending     →  in_progress  →  done
code:      pending     →  in_progress  →  done
review:    pending     →  in_progress  →  done
```

**Fallback:** If a stage stalls for >60s, narrate while it works — explain the orchestrator pattern. If it fails, swap to the pre-recorded clip you put in your Keynote backup slide.

**Talk track (during the wait):** "Three workers, three files, one supervisor reading the results. This is the orchestrator pattern from the Medium post — except now you can see it actually working."

---

### Beat 6 — "Trust but verify."
*This is the moment that sells the security story.*

**Setup:** Pre-bake a `SOUL.md` instruction in the reviewer that asks it to call an external API not on the egress allowlist.

**Command (in a third terminal):**
```bash
openshell term
```

**Expected output:** A TUI prompt appears:
```
[OpenShell] Policy violation requested by agent: reviewer
  Action: HTTP GET https://random-third-party.example/api
  Reason: not in network allowlist
  [a]pprove once  [A]pprove + add to allowlist  [d]eny  [D]eny + log
```

**Approve once, then deny once.** The audience needs to see both branches.

**Fallback:** If the violation doesn't fire (cached allowlist, wrong URL), skip to Beat 7. The story still works without this beat — but if it does fire, this is the slide everyone in the room remembers.

**Talk track (~45s):** "An autonomous agent decided to make a network call. The kernel said no. The operator decides. Every decision is audit-logged. This is the difference between a demo and a deployment."

---

### Beat 7 — "Hot-reload inference."
*Optional. Cut first if pressed for time.*

**Command:** Edit the inference route in your config and reload:
```bash
nemoclaw inference set --agent supervisor --provider nvidia-cloud
nemoclaw inference reload
```

**Expected output:** Reload succeeds without restart. Supervisor's next message comes from the new model. Workers and `STATE.yaml` are unaffected.

**Fallback:** If reload errors, narrate it as "this is hot-reloadable in theory; in practice we're going to skip it on conference Wi-Fi." Audience laughs, you move on.

**Talk track (~20s):** "Inference routing is the only policy that hot-reloads. Filesystem and syscalls are locked at boot. That's by design."

---

### Beat 8 — "Snapshot the whole pipeline."

**Command:**
```bash
nemoclaw snapshot create demo-final
nemoclaw snapshot list
```

**Expected output:**
```
demo-baseline    2026-04-28 09:14   42 MB   stateDirs: [workspace-supervisor, workspace-researcher, workspace-coder, workspace-reviewer]
demo-final       2026-04-28 09:31   58 MB   stateDirs: [workspace-supervisor, workspace-researcher, workspace-coder, workspace-reviewer]
```

**Fallback:** None needed; this command is reliable.

**Talk track (~20s):** "All four workspaces, one command. Pre-PR-2383 this only captured the default workspace and you had to script the rest yourself."

---

### Beat 9 — "Restore."

**Command:**
```bash
nemoclaw snapshot restore demo-baseline
openshell sandbox exec -- cat /sandbox/shared/STATE.yaml
```

**Expected output:** `STATE.yaml` is back to the baseline (empty stages or whatever you set it to pre-demo).

**Fallback:** If restore prints the `chown -R sandbox:sandbox` exit-127 noise (a known issue from the PR's manual validation), narrate it as a known quirk and move on. Files come back fine.

**Talk track (~20s):** "Same pipeline, replayable. Useful for debugging a failed run, useful for shipping a known-good baseline, useful for letting an auditor reproduce a decision."

---

## Closing recap (~60s)

One sentence per beat:

1. The runtime decides what's possible before the agent does.
2. Four agents, four isolated workspaces, one config.
3. Each agent has one job in one file.
4. The supervisor plans and dispatches; it never does the work.
5. State evolves through a shared file, not through prayer.
6. Policy violations stop at the kernel; operators decide.
7. Inference is hot-swappable; security policy isn't.
8. The whole pipeline snapshots as one unit.
9. And restores as one unit.

Then the honesty slide: shared mount, `workspaces list`, and skill propagation are tracked under issue #1260. Don't hide that — flagging known gaps is what makes the rest of the talk credible.

---

## Failure-mode contingency table

| Most likely failure | Pre-positioned fallback |
|---|---|
| Conference Wi-Fi flakes during model pulls | Use local Ollama only; no cloud inference in the demo |
| `nemoclaw start` slow / hangs | `nemoclaw snapshot restore demo-baseline` and retry once |
| Supervisor doesn't dispatch | Nudge with "Plan first, then dispatch."; if still stuck, restore baseline |
| Stage stalls > 90s | Narrate the architecture; if still stalled, cut to pre-recorded clip |
| `openshell term` doesn't fire on Beat 6 | Skip to Beat 7; the security story is still in the slides |
| Snapshot restore prints `chown` exit 127 | Narrate as known issue, proceed; files are fine |
| Display flicker / projector reset | Pause; do not type into a terminal you can't see |

---

## After the talk

- **Hand out** the one-pager (`handout.md`) at the door.
- **Repo link** on the last slide: the `openclaw.json` + four `SOUL.md` files committed somewhere reachable, so anyone can replay the demo themselves.
- **Q&A bait**: end on the rough-edges list. "What we have today vs. what's still tracked under #1260" is the question you actually want the audience to ask.
