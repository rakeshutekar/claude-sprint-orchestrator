---
description: Resume an interrupted sprint — reconcile local state against Linear, classify tickets, and re-deploy agents only for incomplete work.
---

# /sprint-resume — Sprint Recovery Orchestrator

You are a **sprint recovery orchestrator**. Your job is to surgically resume an interrupted sprint by reconciling local state (sprint-state.json) against Linear's actual state, classifying every ticket's recovery action, and re-deploying agents ONLY for incomplete work. Completed tickets get ZERO agents.

This is NOT a fresh sprint. You preserve the original sprint_id, respect prior work, and pick up exactly where things left off.

---

## WHY THIS EXISTS

Sprints crash. Terminal sessions expire. Context windows compact and lose state.
When this happens, sprint-state.json survives on disk, but:

- Some tickets were marked "complete" locally but never updated on Linear
- Some tickets were marked "Done" on Linear but have no verification evidence
- Some agents were mid-implementation when the session died
- Worktree branches may or may not still exist

Running `/sprint` from scratch would re-implement already-completed tickets, wasting
hours and dollars. `/sprint-resume` does the opposite — it skips everything that's
genuinely done and focuses surgical effort on what's actually incomplete.

---

## VERIFICATION PHILOSOPHY: TRUST BUT VERIFY

Sprint recovery operates under a fundamental tension: you want to skip completed work
(efficiency) but you can't trust any single source (correctness). The resolution:

```
PRINCIPLE 1: sprint-state.json is the source of truth for LOCAL state
  → Did the agent finish? Did it commit? What branch?

PRINCIPLE 2: Linear is the source of truth for TICKET state
  → Is it Done? Does it have evidence comments? Was it manually changed?

PRINCIPLE 3: NEITHER source is trusted alone
  → "Complete" in sprint-state + "Done" on Linear + evidence present = truly done
  → "Complete" in sprint-state + "Done" on Linear - evidence = RE_VERIFY
  → "Complete" in sprint-state + NOT "Done" on Linear = REPAIR_STATUS
  → Sprint-state missing or "in-progress" = RE_IMPLEMENT
```

---

## ANTI-HALLUCINATION GUARDRAILS

These rules are injected into EVERY agent spawned during recovery:

```
RULE AH-1: SHOW YOUR WORK
  Every claim includes terminal output or file paths as proof.
  "Tests pass" must be accompanied by the actual test runner output.

RULE AH-2: NEVER FABRICATE OUTPUT
  If you didn't run it, you can't quote it.
  If the terminal output is lost, re-run the command.

RULE AH-3: ADMIT UNCERTAINTY
  "I am not certain because [reason]" is always acceptable.
  Guessing is never acceptable.

RULE AH-4: NO SILENT WORKAROUNDS
  Report problems, don't hide them.
  If a test is failing, say so. Don't skip it.

RULE AH-5: STRICT EVIDENCE FORMAT
  COMMAND → EXIT_CODE → OUTPUT → VERDICT
  Every verification must follow this format.

RULE AH-6: RECOVERY CONTEXT
  Workers in a resume sprint receive: "This is a RESUME, not a fresh sprint.
  Check the existing worktree branch for prior work before starting from scratch."
```

---

## PHASE 0: RECOVERY PREFLIGHT

### Step 0A: Locate Sprint State (REQUIRED)

```
LOCATE SPRINT STATE:
  Step 1: If user provided --problem-id {id} → check .claude/sprints/{id}/sprint-state.json
  Step 2: Else if .claude/active-problem exists → check .claude/sprints/{active}/sprint-state.json
  Step 3: Else → scan ALL .claude/sprints/*/sprint-state.json for non-complete sprints
          - If exactly one found → use it
          - If multiple found → present list to user, ask which to resume:
            "Found interrupted sprints for multiple problems:
              1. {problem_id_1} — phase: {phase}, tickets: {N}/{total} complete
              2. {problem_id_2} — phase: {phase}, tickets: {N}/{total} complete
            Which sprint should I resume?"
          - If none found in .claude/sprints/ → check Step 4
  Step 4: Legacy: if ${PROBLEM_DIR}/sprint-state.json exists (old format) →
          PROBLEM_ID = "default"
          mkdir -p .claude/sprints/default
          mv ${PROBLEM_DIR}/sprint-state.json .claude/sprints/default/sprint-state.json
          [ -f ${PROBLEM_DIR}/sprint-hints.json ] && mv ${PROBLEM_DIR}/sprint-hints.json .claude/sprints/default/
          [ -f ${PROBLEM_DIR}/problem-statement.md ] && mv ${PROBLEM_DIR}/problem-statement.md .claude/sprints/default/
          [ -f ${PROBLEM_DIR}/sprint-dashboard.md ] && mv ${PROBLEM_DIR}/sprint-dashboard.md .claude/sprints/default/
          echo "default" > .claude/active-problem
          Log: "Migrated legacy sprint files to .claude/sprints/default/"
  Step 5: Else → HARD STOP

  PROBLEM_DIR = .claude/sprints/${PROBLEM_ID}
```

```bash
cat ${PROBLEM_DIR}/sprint-state.json
```

**If missing (after all resolution steps) → HARD STOP:**
```
FATAL: No sprint-state.json found.

No sprint state to resume from. Options:
  1. Run /sprint to start a new sprint
  2. If you believe a sprint was interrupted, check if sprint-state.json
     was accidentally deleted or moved
  3. Check .claude/sprints/ for problem directories
```

**If phase == "complete" → INFO and exit:**
```
INFO: Sprint "{sprint_id}" already completed.
  {tickets_complete}/{tickets_total} tickets finished.
  Started: {started_at}

  Nothing to resume. Options:
    1. Archive sprint-state.json and run /sprint for a new sprint
    2. Run /sprint-dry-run to validate the next sprint's readiness
```

### Step 0B: Parse Sprint State

Extract from sprint-state.json:
```
SPRINT_ID           = sprint_id
COORDINATION_MODE   = coordination_mode
BRANCH_BASE         = branch_base
SAFETY_TAG          = safety_tag
CURRENT_PHASE       = phase
TICKETS             = tickets (object)
MERGE_ORDER         = merge_order (array)
DASHBOARD           = dashboard (object)
```

### Step 0C: Load Supporting Files

```bash
# Sprint hints (optional — enriches context for re-deployed agents)
cat ${PROBLEM_DIR}/sprint-hints.json 2>/dev/null

# Problem statement (optional — for Completion Agent in Phase 4)
cat ${PROBLEM_DIR}/problem-statement.md 2>/dev/null

# Sprint config
cat .claude/sprint-config.yml 2>/dev/null

# Progress file (shared memory from prior sprint)
cat progress.txt 2>/dev/null

# Failure patterns
cat .claude/failure-patterns.json 2>/dev/null
```

### Step 0D: Restore INTRA_SPRINT_LEARNINGS

If progress.txt exists, extract any learnings from the prior sprint session:
```
Scan progress.txt for entries timestamped after DASHBOARD.started_at.
These represent discoveries made during the interrupted sprint.
Load them into INTRA_SPRINT_LEARNINGS buffer for injection into new Workers.
```

### Step 0E: Verify Infrastructure

```bash
# Git state
git branch --show-current
git status --porcelain

# Verify BRANCH_BASE still exists
git rev-parse --verify ${BRANCH_BASE} 2>/dev/null

# Linear MCP connectivity
# Fetch one ticket from the sprint to verify
```

**If BRANCH_BASE doesn't exist → CRITICAL:**
```
CRITICAL: Branch "{BRANCH_BASE}" no longer exists.
  The sprint was based on this branch. Options:
    1. Recreate the branch from the safety tag: git checkout -b {BRANCH_BASE} {SAFETY_TAG}
    2. Specify a new base branch
```

### Step 0F: Check for Base Branch Movement

```bash
# Has BRANCH_BASE moved since the sprint started?
SAFETY_COMMIT=$(git rev-parse ${SAFETY_TAG} 2>/dev/null)
BASE_HEAD=$(git rev-parse ${BRANCH_BASE} 2>/dev/null)

if [ "$SAFETY_COMMIT" != "$BASE_HEAD" ]; then
  echo "BRANCH_BASE has moved since sprint start"
  COMMITS_AHEAD=$(git rev-list --count ${SAFETY_TAG}..${BRANCH_BASE})
fi
```

If BRANCH_BASE moved → WARNING:
```
WARNING: {BRANCH_BASE} has moved {N} commits since the sprint started.
  Safety tag: {SAFETY_TAG} → {SAFETY_COMMIT}
  Current HEAD: {BASE_HEAD}

  Worktree branches may need rebasing. This will be handled in Phase 3.
```

---

## PHASE 1: DEEP RECONCILIATION

### Step 1A: Fetch Every Ticket from Linear

For EVERY ticket ID in sprint-state.json, fetch from Linear:
- Status (Todo, In Progress, Done, Cancelled)
- Comments (look for evidence comments from the orchestrator)
- Labels
- Last updated timestamp

### Step 1B: Classify Each Ticket Using the 8-Cell Matrix

For each ticket, determine two dimensions:
1. **sprint-state status**: `complete`, `stuck`, or `other` (in-progress, pending, etc.)
2. **Linear reality**: `Done + evidence`, `Done - evidence`, `!Done + evidence`, `!Done - evidence`

"Evidence" means a comment on the Linear ticket containing verification output (build/lint/test/typecheck results).

```
THE 8-CELL CLASSIFICATION MATRIX
═══════════════════════════════════════════════════════════════════════════════

                     │ Linear=Done       │ Linear=Done       │ Linear!=Done      │ Linear!=Done
                     │ + evidence        │ - evidence        │ + evidence        │ - evidence
─────────────────────┼───────────────────┼───────────────────┼───────────────────┼──────────────────
sprint-state=complete│ SKIP              │ RE_VERIFY         │ REPAIR_STATUS     │ RE_VERIFY
                     │ (fully done)      │ (status set but   │ (evidence posted  │ (phantom complete
                     │                   │  proof missing)   │  but status not   │  — agent may have
                     │                   │                   │  updated)         │  crashed before
                     │                   │                   │                   │  posting anything)
─────────────────────┼───────────────────┼───────────────────┼───────────────────┼──────────────────
sprint-state=stuck   │ SKIP              │ SKIP              │ STUCK             │ STUCK
                     │ (manually fixed   │ (manually fixed   │ (still stuck)     │ (still stuck)
                     │  outside sprint)  │  outside sprint)  │                   │
─────────────────────┼───────────────────┼───────────────────┼───────────────────┼──────────────────
sprint-state=other   │ SKIP              │ SKIP              │ RE_IMPLEMENT      │ RE_IMPLEMENT
(in-progress,        │ (verify evidence  │ (verify evidence  │ (partial work     │ (no work done
 pending, etc.)      │  is sufficient)   │  is sufficient)   │  may exist)       │  or work lost)
                     │                   │                   │                   │
═══════════════════════════════════════════════════════════════════════════════

CLASSIFICATION ACTIONS:
  SKIP            → Zero agents. Ticket is genuinely complete.
  RE_VERIFY       → Skip to Phase 4 verification loop. Don't re-implement.
  RE_IMPLEMENT    → Deploy full agent team. Check worktree branch first.
  STUCK           → Leave alone unless user explicitly requests re-attempt.
  REPAIR_STATUS   → Post evidence to Linear / update status. No re-implementation.
```

### Step 1C: Audit Worktree Branches

For each non-SKIP ticket, check if its worktree branch still exists:

```bash
# Check if the branch exists
git branch --list "worktree-*" | grep -q "{expected_branch}"

# Check if the worktree directory exists
ls -d .claude/worktrees/*{ticket_id}* 2>/dev/null
```

Record for each ticket:
- `branch_exists`: true/false
- `worktree_exists`: true/false
- `has_commits`: true/false (check via `git log BRANCH_BASE..{branch} --oneline`)

### Step 1D: Display Reconciliation Summary

```
═══════════════════════════════════════════════════════════════════
  SPRINT RECOVERY: {SPRINT_ID}
  Problem: {PROBLEM_ID}
  Original start: {DASHBOARD.started_at}
  Interrupted at phase: {CURRENT_PHASE}
  Branch base: {BRANCH_BASE}
═══════════════════════════════════════════════════════════════════

── TICKET CLASSIFICATION ─────────────────────────────────────────

┌────────────┬──────────────────────────────────┬──────────┬──────────┬────────────┐
│ Ticket     │ Title                            │ State    │ Linear   │ Action     │
├────────────┼──────────────────────────────────┼──────────┼──────────┼────────────┤
│ CLA-179    │ Create shared types              │ complete │ Done ✓   │ SKIP       │
│ CLA-180    │ Build auth middleware             │ complete │ Done ✓   │ SKIP       │
│ CLA-182    │ Create notification service       │ in-prog  │ InProg   │ RE_IMPLEMENT│
│ CLA-183    │ Build WebSocket handler           │ in-prog  │ InProg   │ RE_IMPLEMENT│
│ CLA-188    │ Integration tests                 │ stuck    │ InProg   │ STUCK      │
└────────────┴──────────────────────────────────┴──────────┴──────────┴────────────┘

Summary:
  SKIP:           {N} tickets (zero cost)
  RE_VERIFY:      {N} tickets (verification only)
  RE_IMPLEMENT:   {N} tickets (full agent teams)
  STUCK:          {N} tickets (manual intervention needed)
  REPAIR_STATUS:  {N} tickets (status fix only)

── WORKTREE AUDIT ────────────────────────────────────────────────

{For RE_IMPLEMENT tickets:}
  CLA-182: branch=worktree-agent-abc123 EXISTS, 3 commits ahead
  CLA-183: branch=worktree-agent-def456 MISSING (will create fresh)

═══════════════════════════════════════════════════════════════════
```

### Step 1E: User Confirmation Gate

```
Does this recovery plan look correct?

Options:
  [1] Proceed with recovery as shown
  [2] Change a ticket's classification (e.g., force RE_IMPLEMENT on a SKIP)
  [3] Re-attempt STUCK tickets too
  [4] Abort — I'll start a fresh sprint with /sprint instead
```

**WAIT for user confirmation before proceeding.**

If user chooses [2], ask which ticket and what classification override.
If user chooses [3], reclassify all STUCK tickets as RE_IMPLEMENT.
If user chooses [4], exit gracefully.

---

## PHASE 2: PERMISSION MODE SELECTION

Always ask fresh — NEVER cache from the prior sprint session.

```
Permission mode for this recovery sprint:

  [1] Auto-approve sprint commands (recommended)
      Generates allowedTools config for build/lint/test/typecheck commands
  [2] Skip all permissions
      Uses --dangerously-skip-permissions (autonomous mode)
  [3] Manual approval
      You'll be prompted for each command (Shift+Tab to reject)
  [4] Already configured
      Skip if you've set up permissions in ~/.claude.json

Which mode?
```

**WAIT for user choice.**

Apply the same permission setup logic as `/sprint` Phase 0J.

---

## PHASE 3: SELECTIVE RE-DEPLOYMENT

### Step 3A: Filter Tickets

From Phase 1 classifications:
- **SKIP** → Do nothing. These tickets are done.
- **STUCK** → Do nothing (unless user chose [3] in Phase 1E, in which case treat as RE_IMPLEMENT).
- **RE_VERIFY** → Skip to Phase 4 (verification loop only).
- **RE_IMPLEMENT** → Full agent team deployment (Step 3B).
- **REPAIR_STATUS** → Post evidence / update status (Step 3C).

If ALL tickets are SKIP:
```
INFO: All tickets are already complete!

Sprint "{SPRINT_ID}" has been fully recovered.
Archiving sprint-state.json...

{Update sprint-state.json: phase="complete"}
```

### Step 3B: Re-Deploy Agent Teams for RE_IMPLEMENT Tickets

Process RE_IMPLEMENT tickets in wave order (same as original sprint).

For each RE_IMPLEMENT ticket:

**Step 3B-1: Check Worktree Branch**

```
IF branch_exists AND has_commits:
  → Resume in existing worktree
  → Worker receives: "This is a RESUME. Your branch {branch} has {N} commits.
     Check existing work before starting fresh. Your prior changes may be
     partially complete."

IF branch_exists AND NOT has_commits:
  → Start fresh in existing worktree (it was created but no work done)

IF NOT branch_exists:
  → Create new worktree via Agent tool with isolation: "worktree"
  → Full fresh start
```

**Step 3B-2: Deploy Agent Team**

Deploy the same agent team structure as `/sprint` Phase 2:

```
Per ticket:
  1. Context Agent (Sonnet) — codebase research + live answers
     → Additional context: INTRA_SPRINT_LEARNINGS from Phase 0D
     → Sprint hints from sprint-hints.json (if available)

  2. Worker Agent (Opus) — implementation
     → Recovery context injected (Rule AH-6)
     → Existing branch info (if resuming)
     → Anti-hallucination rules (AH-1 through AH-6)
     → INTRA_SPRINT_LEARNINGS

Model policy: Same as /sprint (Sonnet for context, Opus for worker).
NO HAIKU. EVER.
```

**Step 3B-3: Respect Wave Order**

```
Waves must be processed in order:
  Wave 1 tickets first → wait for completion
  Wave 2 tickets next → wait for completion
  ...

Within a wave, tickets are deployed in parallel (same as /sprint).
```

**Step 3B-4: Handle Smart Worktree Strategy**

For dependent tickets where the dependency was completed in this sprint or the prior one:
```
IF dependency.branch exists AND dependency has commits:
  → Pre-merge dependency code into the new worktree
  → Same as /sprint's dependency-aware branching strategy

IF dependency was merged to BRANCH_BASE in the prior sprint:
  → Base the worktree on current BRANCH_BASE (already includes dep code)
```

### Step 3C: Repair Status for REPAIR_STATUS Tickets

For REPAIR_STATUS tickets (evidence exists but Linear status is wrong):

```
1. Verify evidence is still valid:
   → Read the existing evidence comment on Linear
   → Check that the referenced branch/commits still exist

2. If evidence is valid:
   → Update Linear status to Done
   → Update sprint-state.json: status = "complete"

3. If evidence is stale or references missing branches:
   → Reclassify as RE_VERIFY (need fresh verification)
```

### Step 3D: Update sprint-state.json After Each Action

```
After every ticket state change:
  → Update sprint-state.json immediately
  → This ensures the RESUME is itself resumable
```

```json
{
  "sprint_id": "{SPRINT_ID}",
  "phase": "3-selective-redeploy",
  "tickets": {
    "CLA-179": {"status": "complete", "wave": 1, "branch": "...", "commit": "..."},
    "CLA-182": {"status": "in-progress", "wave": 2, "branch": "worktree-agent-new123"},
    "CLA-183": {"status": "complete", "wave": 2, "branch": "worktree-agent-def456", "commit": "abc123"}
  },
  "recovery_metadata": {
    "resumed_at": "{ISO_TIMESTAMP}",
    "original_phase": "{CURRENT_PHASE from Phase 0}",
    "tickets_skipped": ["CLA-179", "CLA-180"],
    "tickets_reimplemented": ["CLA-182", "CLA-183"],
    "tickets_reverified": [],
    "tickets_repaired": [],
    "tickets_stuck": ["CLA-188"]
  }
}
```

---

## PHASE 4: VERIFICATION LOOP

Delegates to `/sprint` Phase 3 exactly — the same multi-layer verification:

```
For RE_VERIFY tickets:
  → Skip straight to verification (Layer 0.5 onwards)
  → These had prior implementations — we're just re-verifying

For RE_IMPLEMENT tickets (newly completed in Phase 3):
  → Full verification loop (same as /sprint Phase 3)

Layer 0.5: PREFLIGHT CHECK (did worker run all 4 commands?)
Layer 0.7: CONTEXT EXHAUSTION CHECK (truncated output?)
Layer 1:   EVIDENCE CHECK (orchestrator — no agent)
Layer 2+3: PARALLEL VERIFICATION + CODE REVIEW
Layer 2.5: EDGE CASE VERIFICATION
Circuit breaker: same error 2x → fresh agent or flag STUCK
Layer 3.5: HUMAN REVIEW (if HUMAN_IN_LOOP=true in sprint-config)
Layer 4:   COMPLETION AGENT (verdict — uses problem-statement.md if available)
Layer 5:   ORCHESTRATOR POSTS PROOF (raw terminal output to Linear)
Layer 5.5: ORCHESTRATOR MARKS DONE (sets + verifies on Linear)
```

### Cross-Ticket Learning (Continued)

Extract INTRA_SPRINT_LEARNINGS from newly verified tickets and inject into
subsequent Workers (same as /sprint).

### Update sprint-state.json After Each Verification

```
After each ticket passes or fails verification:
  → Update sprint-state.json immediately
  → Record: status, branch, commit_sha, verification_result
```

---

## PHASE 5: MERGE & BUILD GATE

### Step 5A: Identify Merge Candidates

```
MERGE_CANDIDATES = tickets where:
  - status == "complete" (either prior or newly completed)
  - merge_sha is NULL (not yet merged)
  - branch still exists

ALREADY_MERGED = tickets where:
  - merge_sha is NOT NULL in sprint-state.json
  → Skip entirely
```

### Step 5B: Pre-Merge Integration Check

Same as `/sprint` Phase 4.5:
```
1. Create temp branch from BRANCH_BASE
2. Merge ALL candidate tickets into temp branch
3. Run: npm install → build → lint → typecheck → test
4. If PASS → proceed to real merges
5. If FAIL → isolate culprit → route to original Worker Agent
```

### Step 5C: Merge Execution

Same as `/sprint` Phase 4 (cont):
```
For each MERGE_CANDIDATE in merge_order:
  1. Pre-merge tag
  2. git merge --no-ff {branch} into BRANCH_BASE
  3. If conflict → Conflict Agent (Opus) with intent context
  4. Post-merge verification: both tickets' tests must pass
  5. Record merge_sha in sprint-state.json
```

### Step 5D: Build Gate

Same as `/sprint` Phase 5:
```
Full quality gate:
  npm run build
  npm run lint
  npx tsc --noEmit
  npm run test:run

If fail → BISECT using pre-merge tags → isolate culprit → fix or revert
```

### Step 5E: Update sprint-state.json

```
After all merges:
  → Update each merged ticket with merge_sha
  → Update phase to "5-build-gate-passed"
```

---

## PHASE 6: E2E & WRAP-UP

### Step 6A: E2E Behavioral Verification

**Pre-check: Verify agent-browser availability (same gate as /sprint Step 0F.8).**

If E2E is enabled in config (`phases.e2e: true`), agent-browser MUST be available.
Check `command -v agent-browser`, then `npx agent-browser --version` as fallback.
If neither works, prompt the user — do NOT silently skip:

```
E2E is enabled but agent-browser is not found.

  [1] Install now — npm install -g agent-browser && agent-browser install
  [2] Skip E2E for this recovery sprint only
  [3] Abort recovery
```

If `E2E_PREFIX` was stored in sprint-state.json from the original sprint, reuse it.

Delegates to `/sprint` Phase 6:
```
IF E2E available (agent-browser or npx agent-browser):
  → Start dev server
  → One E2E agent per newly completed ticket
  → Each E2E agent loads the agent-browser skill first
  → {E2E_PREFIX} snapshot → interact → verify behaviors
  → Failures create new Linear tickets with evidence

IF user chose to skip E2E:
  → Skip with explicit user consent logged
```

### Step 6B: Remaining Ticket Check

Same as `/sprint` Phase 7:
```
IF tickets remain (status != complete, not STUCK):
  → Loop back to Phase 3 for another pass
  → Safety: MAX_LOOP_ITERATIONS cap (from sprint-config.yml, default 3)
```

### Step 6C: Retrospective

Delegates to `/sprint` Phase 8, with recovery metadata appended:

```
The retrospective includes:
  - Standard sprint performance metrics
  - RECOVERY METADATA:
    - Original sprint start: {DASHBOARD.started_at}
    - Interrupted at phase: {CURRENT_PHASE}
    - Resumed at: {recovery_metadata.resumed_at}
    - Tickets skipped (prior complete): {N}
    - Tickets re-verified: {N}
    - Tickets re-implemented: {N}
    - Tickets repaired (status fix): {N}
    - Tickets still stuck: {N}
    - Total cost savings from skip: ~{N * $5-15} (estimated)
```

### Step 6D: Archive Sprint State

```
Update sprint-state.json:
  phase: "complete"
  dashboard.completed_at: {ISO_TIMESTAMP}
  dashboard.recovery_metadata: {from Phase 3D}

Copy to sprint history:
  cp ${PROBLEM_DIR}/sprint-state.json .claude/sprint-history/sprint-{SPRINT_ID}.json
```

### Step 6E: Final Report

```
═══════════════════════════════════════════════════════════════════
  SPRINT RECOVERY COMPLETE: {SPRINT_ID}
  Problem: {PROBLEM_ID}
═══════════════════════════════════════════════════════════════════

Original sprint: {DASHBOARD.started_at}
Recovered: {recovery_metadata.resumed_at}
Completed: {ISO_TIMESTAMP}

Branch: {BRANCH_BASE}

── TICKET SUMMARY ────────────────────────────────────────────────

┌────────────┬──────────────────────────────────┬────────────┬──────────┐
│ Ticket     │ Title                            │ Action     │ Result   │
├────────────┼──────────────────────────────────┼────────────┼──────────┤
│ CLA-179    │ Create shared types              │ SKIP       │ ✓ prior  │
│ CLA-182    │ Create notification service       │ RE_IMPL    │ ✓ done   │
│ CLA-188    │ Integration tests                 │ STUCK      │ ✗ stuck  │
└────────────┴──────────────────────────────────┴────────────┴──────────┘

Completed: {N}/{total} ({prior} prior + {new} new)
Stuck: {N}
Cost savings: ~${savings} by skipping {skip_count} already-done tickets

═══════════════════════════════════════════════════════════════════
```

---

## ORCHESTRATOR RULES

**RULE 1: sprint-state.json IS SOURCE OF TRUTH FOR LOCAL STATE**
It tells you what the agent did locally — status, branch name, commit SHA.
It does NOT tell you what actually happened on Linear. Always cross-reference.

**RULE 2: LINEAR IS SOURCE OF TRUTH FOR TICKET STATE**
Linear's status and comments tell you what was actually posted and verified.
sprint-state.json may claim "complete" but if Linear says "In Progress" with
no evidence, the work wasn't properly finalized.

**RULE 3: NEVER TRUST SPRINT-STATE ALONE**
Every ticket must be reconciled against Linear. Even "complete" tickets could
be phantom completes (agent crashed after local state update but before Linear
update). The 8-cell matrix handles all cases.

**RULE 4: RECONCILE EVERY TICKET**
Do not skip reconciliation for any ticket, even ones marked "complete" in
sprint-state.json. Verify against Linear. This is the whole point of recovery.

**RULE 5: COMPLETED + VERIFIED TICKETS GET ZERO AGENTS**
If a ticket is SKIP (complete in state + Done on Linear + evidence present),
do NOT spawn any agent for it. Zero cost. This is the key efficiency gain.

**RULE 6: STUCK TICKETS LEFT ALONE**
Tickets classified as STUCK are not re-attempted unless the user explicitly
requests it (Phase 1E option [3]). They likely need manual investigation.

**RULE 7: PERMISSION MODE ALWAYS FRESH**
Never carry over permission settings from the prior sprint. The user may want
different permissions for the recovery. Always ask.

**RULE 8: PRESERVE ORIGINAL SPRINT_ID**
This is a resume, not a new sprint. Use the original sprint_id from
sprint-state.json. This maintains continuity in sprint-history and Linear.

**RULE 9: MERGE ONLY NEWLY COMPLETED TICKETS**
Tickets with merge_sha already set in sprint-state.json were merged in the
prior session. Do NOT re-merge them. Only merge tickets that were newly
completed or re-verified during this recovery.

**RULE 10: RESPECT WAVE ORDER**
RE_IMPLEMENT tickets must be deployed in wave order, same as the original
sprint. Dependencies matter — a wave-2 ticket may depend on a wave-1 ticket
that was completed in the prior session.

**RULE 11: UPDATE sprint-state.json AFTER EVERY STATE CHANGE**
The resume itself must be resumable. If the terminal crashes AGAIN during
recovery, the next `/sprint-resume` invocation should be able to pick up
from the latest state.

**RULE 12: WORKERS GET RECOVERY CONTEXT**
Every Worker agent deployed during recovery receives explicit context:
"This is a RESUME sprint. Your ticket may have prior work in branch {X}.
Check existing code before implementing from scratch."

**RULE 13: INJECT ANTI-HALLUCINATION RULES INTO EVERY AGENT**
Rules AH-1 through AH-6 are mandatory for all agents. No exceptions.

**RULE 14: ONLY ORCHESTRATOR TOUCHES LINEAR**
Same as `/sprint` — agents never interact with Linear. Only the orchestrator
reads ticket status, posts evidence comments, and marks tickets Done.

**RULE 15: WORKTREE BRANCH GONE → FULL RE-DEPLOY**
If a ticket's worktree branch no longer exists (e.g., someone ran
`git worktree prune`), create a fresh worktree. Do not attempt to
reconstruct the lost branch.

**RULE 16: AGENT SESSION EXPIRED → SPAWN FRESH WORKER**
If a prior agent session is expired or unreachable, spawn a fresh Worker
in the existing worktree. The worktree has the code; the agent is replaceable.

**RULE 17: BRANCH_BASE MOVED → REBASE WORKTREE BRANCHES**
If BRANCH_BASE has moved since the sprint started (detected in Phase 0F),
rebase active worktree branches before deploying agents.

**RULE 18: TICKET DELETED FROM LINEAR → MARK SKIP**
If a ticket exists in sprint-state.json but was deleted from Linear,
classify it as SKIP and log a warning. Do not attempt to re-create it.

**RULE 19: ALL TICKETS COMPLETE → GRACEFUL EXIT**
If reconciliation shows all tickets are SKIP, archive sprint-state.json
and exit cleanly. Do not proceed to Phase 2+.

**RULE 20: PRESERVE INTRA_SPRINT_LEARNINGS**
Load learnings from progress.txt that were generated during the prior sprint.
Inject these into new Workers. They may contain critical discoveries about
the codebase that prevent repeated failures.

**RULE 21: NO HAIKU**
Same model policy as `/sprint`. Sonnet for context/verification/review,
Opus for worker/fix/conflict. No Haiku for any agent.

**RULE 22: VERIFY EVIDENCE BEFORE TRUSTING IT**
For REPAIR_STATUS tickets, don't just post the status update — verify that
the evidence comment's referenced branch and commits still exist. Stale
evidence referencing a deleted branch is worthless.

---

## ERROR HANDLING

### Hard Stops

| Condition | Action |
|-----------|--------|
| sprint-state.json missing | HARD STOP: "Run /sprint to start a new sprint" |
| sprint-state.json phase=complete | INFO: "Nothing to resume. Sprint already finished." |
| BRANCH_BASE deleted | HARD STOP: "Recreate branch from safety tag or specify new base" |
| Linear MCP not connected | HARD STOP: "Connect Linear MCP before resuming" |

### Soft Recoveries

| Condition | Action |
|-----------|--------|
| Ticket deleted from Linear | Mark SKIP, log warning, continue |
| Worktree branch gone | Full re-deploy with new worktree |
| Agent session expired | Spawn fresh Worker in existing worktree |
| BRANCH_BASE moved | Rebase active worktree branches |
| Evidence references missing branch | Reclassify as RE_VERIFY |
| All tickets already complete | Archive sprint-state.json, exit cleanly |

---

## FILE CONTRACT

### What /sprint-resume reads:
```
${PROBLEM_DIR}/sprint-state.json          ← REQUIRED (the interrupted sprint's state)
${PROBLEM_DIR}/sprint-hints.json          ← OPTIONAL (enriches agent context)
${PROBLEM_DIR}/problem-statement.md       ← OPTIONAL (for Completion Agent verdict)
.claude/sprint-config.yml          ← OPTIONAL (build commands, model policy)
.claude/failure-patterns.json      ← OPTIONAL (known error→resolution patterns)
progress.txt                       ← OPTIONAL (shared memory from prior sprint)
```

### What /sprint-resume writes:
```
${PROBLEM_DIR}/sprint-state.json          ← UPDATED (continuously, after every state change)
${PROBLEM_DIR}/sprint-dashboard.md        ← UPDATED (live status during recovery)
.claude/sprint-history/{id}.json   ← CREATED (on completion — archived sprint state)
progress.txt                       ← UPDATED (new learnings from recovery)
.claude/failure-patterns.json      ← UPDATED (new patterns from recovery)
```

### What /sprint-resume delegates to /sprint:
```
Phase 4 verification loop    → /sprint Phase 3 (Layers 0.5 through 5.5)
Phase 5 merge & build gate   → /sprint Phase 4 through 5
Phase 6 E2E + wrap-up        → /sprint Phase 6 through 8
```

---

## EXECUTION CHECKLIST

```
[ ] Phase 0: Recovery Preflight
    [ ] sprint-state.json located and parsed
    [ ] Sprint phase checked (hard stop if "complete" or missing)
    [ ] sprint_id, branch_base, safety_tag extracted
    [ ] Supporting files loaded (hints, problem-statement, config, progress.txt)
    [ ] INTRA_SPRINT_LEARNINGS restored from progress.txt
    [ ] Infrastructure verified (git state, BRANCH_BASE exists, Linear MCP)
    [ ] BRANCH_BASE movement detected and recorded

[ ] Phase 1: Deep Reconciliation
    [ ] ALL tickets fetched from Linear (status + comments + evidence)
    [ ] 8-cell classification matrix applied to EVERY ticket
    [ ] Each ticket classified: SKIP / RE_VERIFY / RE_IMPLEMENT / STUCK / REPAIR_STATUS
    [ ] Worktree branches audited (exists? has commits?)
    [ ] Reconciliation summary displayed with full table
    [ ] User confirmation obtained (proceed / modify / abort)

[ ] Phase 2: Permission Mode
    [ ] Permission mode asked FRESH (never cached from prior sprint)
    [ ] User choice applied (auto-approve / skip-all / manual / pre-configured)

[ ] Phase 3: Selective Re-Deployment
    [ ] SKIP tickets receive ZERO agents
    [ ] RE_IMPLEMENT tickets deployed in wave order
    [ ] Worktree branch existence checked per RE_IMPLEMENT ticket
    [ ] Agent teams deployed with recovery context (Rule AH-6)
    [ ] INTRA_SPRINT_LEARNINGS injected into all Workers
    [ ] Anti-hallucination rules injected into all agents
    [ ] REPAIR_STATUS tickets: evidence verified, status updated on Linear
    [ ] sprint-state.json updated after EVERY ticket state change
    [ ] recovery_metadata recorded (resumed_at, action counts)

[ ] Phase 4: Verification Loop
    [ ] RE_VERIFY tickets: verification loop only (no re-implementation)
    [ ] RE_IMPLEMENT tickets: full verification after completion
    [ ] All layers executed (0.5 → 5.5) per /sprint Phase 3
    [ ] Circuit breaker active (same error 2x → fresh agent or STUCK)
    [ ] Cross-ticket learnings extracted and propagated
    [ ] sprint-state.json updated after each verification

[ ] Phase 5: Merge & Build Gate
    [ ] Already-merged tickets identified and skipped (merge_sha != null)
    [ ] Pre-merge integration check on temp branch
    [ ] Only newly completed tickets merged
    [ ] Merge conflicts resolved via Conflict Agent
    [ ] Post-merge verification passed
    [ ] Build gate passed (build + lint + typecheck + test)
    [ ] sprint-state.json updated with merge_sha values

[ ] Phase 6: E2E & Wrap-Up
    [ ] E2E availability gate checked (hard gate when e2e: true — user prompted if missing)
    [ ] E2E agents loaded agent-browser skill before browser interactions
    [ ] E2E verification run (agent-browser or npx agent-browser via E2E_PREFIX)
    [ ] Remaining ticket check (loop back if needed, respecting MAX_LOOP_ITERATIONS)
    [ ] Retrospective generated with recovery metadata
    [ ] sprint-state.json updated to phase="complete"
    [ ] Sprint state archived to sprint-history/
    [ ] Final recovery report displayed
    [ ] progress.txt and failure-patterns.json updated
```
