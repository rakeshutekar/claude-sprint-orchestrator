---
description: Pre-validate a sprint — check Linear tickets, compute deployment waves, predict file conflicts, and verify infrastructure. Read-only, changes nothing.
---

# /sprint-dry-run — Sprint Readiness Audit

You are a **sprint readiness auditor**. Your job is to validate every prerequisite, predict conflicts, surface risks, and produce a go/no-go verdict BEFORE agents spawn. You change nothing — no files created, no commits, no state mutations, no Linear updates.

Think of this as a "preflight checklist" for `/sprint`. Run it after `/tickets` and before `/sprint`.

---

## WHY THIS EXISTS

Sprints are expensive — a 5-ticket sprint spawns 40-60 agent windows and can cost $15-80+.
Without pre-validation, users commit to this cost blindly:

- Tickets may have drifted on Linear (renamed, closed, reassigned)
- The plan may be stale (code changed since `/tickets` ran)
- File conflicts between tickets may exist but aren't visible until merge phase
- Infrastructure may be broken (build commands missing, worktree .gitignore absent)
- A prior sprint-state.json may be sitting around from a crash (needs `/sprint-resume`, not `/sprint`)

`/sprint-dry-run` catches all of this in ~30 seconds with zero cost beyond the orchestrator's own context.

---

## STEP 0-PRE: RESOLVE PROBLEM DIRECTORY

Before any other work, determine which problem directory to use:

```
RESOLVE PROBLEM DIRECTORY:
  Step 1: If user provided a problem ID as argument → PROBLEM_ID = that argument
  Step 2: Else if .claude/active-problem exists → PROBLEM_ID = contents of that file
  Step 3: Else if exactly one directory under .claude/sprints/ → PROBLEM_ID = its name
  Step 4: Else if legacy singleton files exist (.claude/problem-statement.md, .claude/sprint-hints.json) →
          PROBLEM_ID = "default"
          mkdir -p .claude/sprints/default
          mv .claude/problem-statement.md .claude/sprints/default/ 2>/dev/null
          mv .claude/sprint-hints.json .claude/sprints/default/ 2>/dev/null
          mv .claude/sprint-state.json .claude/sprints/default/ 2>/dev/null
          mv .claude/sprint-dashboard.md .claude/sprints/default/ 2>/dev/null
          mv .claude/sprint-preflight.json .claude/sprints/default/ 2>/dev/null
          echo "default" > .claude/active-problem
          echo "Migrated legacy sprint files to .claude/sprints/default/"
  Step 5: Else → HARD STOP:
          "No active problem found. Run /define first to create a problem statement,
           or pass a problem ID: /sprint-dry-run <problem-id>"

  PROBLEM_DIR = .claude/sprints/${PROBLEM_ID}
```

Display: `Active problem: ${PROBLEM_ID} (${PROBLEM_DIR}/)`

---

## PHASE 0: PREFLIGHT VALIDATION

### Step 0A: Locate sprint-hints.json (REQUIRED)

```bash
# sprint-hints.json is the primary input — produced by /tickets
cat ${PROBLEM_DIR}/sprint-hints.json
```

**If missing → HARD STOP:**
```
FATAL: ${PROBLEM_DIR}/sprint-hints.json not found.

This file is produced by /tickets. Run /tickets first to generate a plan,
then re-run /sprint-dry-run to validate it before sprinting.
```

### Step 0B: Parse and Validate sprint-hints.json Schema

Verify all required fields exist:

```
REQUIRED FIELDS:
  generated_at        — ISO timestamp (string)
  plan_commit         — short SHA (string)
  plan_doc            — path to plan document (string)
  tickets             — object with ticket IDs as keys
  total_tickets       — number
  total_edge_cases    — number

PER-TICKET REQUIRED FIELDS (tickets.{TICKET_ID}):
  title               — string
  complexity           — "S" | "M" | "L"
  wave                — number (≥1)
  dependencies         — array of ticket IDs
  files_to_create      — array of file paths
  files_to_modify      — array of file paths
  edge_case_count      — number
```

**If any required field is missing → report as CRITICAL finding.**

### Step 0C: Load Optional Inputs

```bash
# Problem statement (optional — enriches coverage preview)
cat ${PROBLEM_DIR}/problem-statement.md 2>/dev/null

# Sprint config (optional — validates commands exist)
cat .claude/sprint-config.yml 2>/dev/null
```

### Step 0D: Staleness Check

Compare `plan_commit` from sprint-hints.json against current HEAD:

```bash
PLAN_COMMIT=$(jq -r '.plan_commit' ${PROBLEM_DIR}/sprint-hints.json)
HEAD_COMMIT=$(git rev-parse --short HEAD)

# Count commits since plan was generated
COMMITS_SINCE=$(git rev-list --count ${PLAN_COMMIT}..HEAD 2>/dev/null || echo "UNKNOWN")

# List files changed since plan commit
FILES_CHANGED=$(git diff --name-only ${PLAN_COMMIT}..HEAD 2>/dev/null)
```

Record staleness:
- `COMMITS_SINCE == 0` → FRESH
- `COMMITS_SINCE == 1-5` → SLIGHTLY_STALE (WARNING)
- `COMMITS_SINCE > 5` → STALE (HIGH)
- `PLAN_COMMIT not found` → UNKNOWN (CRITICAL — plan commit may have been rebased away)

If FILES_CHANGED overlaps with any ticket's `files_to_create` or `files_to_modify` → flag as CRITICAL:
```
CRITICAL: File {path} was modified since the plan was generated.
  Ticket {TICKET_ID} plans to {create|modify} this file.
  The plan may be outdated. Consider re-running /tickets.
```

---

## PHASE 1: LINEAR RECONCILIATION

### Step 1A: Verify Linear MCP Connectivity

Use the Linear MCP to fetch a single ticket as a connectivity test:

```
Pick the first ticket ID from sprint-hints.json.
Fetch it via Linear MCP (list_issues or get_issue).
If the MCP call fails → CRITICAL: "Linear MCP not connected or not authenticated."
```

### Step 1B: Fetch All Tickets from Linear

For EVERY ticket ID in sprint-hints.json, fetch from Linear:
- Status (Todo, In Progress, Done, Cancelled, etc.)
- Title
- Labels
- Assignee
- Dependencies (blocked-by relations)

### Step 1C: Cross-Reference Against sprint-hints.json

Build a reconciliation table:

```
┌────────────┬──────────────────────────────────────┬──────────────┬──────────────┐
│ Ticket     │ Title                                │ Hints Status │ Linear Status│
├────────────┼──────────────────────────────────────┼──────────────┼──────────────┤
│ {ID}       │ {title from hints}                   │ planned      │ {actual}     │
│            │ {title from Linear if different}      │              │              │
└────────────┴──────────────────────────────────────┴──────────────┴──────────────┘
```

Flag mismatches:

| Condition | Severity | Message |
|-----------|----------|---------|
| Ticket not found on Linear | CRITICAL | `{ID} does not exist on Linear — was it deleted?` |
| Title differs by >30% (Levenshtein) | WARNING | `{ID} title drift: hints="{A}" linear="{B}"` |
| Linear status = Done | HIGH | `{ID} is already Done on Linear — skip or re-open?` |
| Linear status = Cancelled | CRITICAL | `{ID} was Cancelled on Linear` |
| Linear has tickets NOT in hints | INFO | `Orphan: {ID} "{title}" exists on Linear but not in sprint-hints.json` |
| Dependency mismatch | HIGH | `{ID} depends on {DEP_ID} in hints, but Linear has no blocking relation` |

### Step 1D: Dependency Validation

For each ticket's `dependencies` array:
1. Verify the dependency ticket exists in sprint-hints.json
2. Verify the dependency ticket exists on Linear
3. Verify the dependency is in a lower or equal wave number
4. Flag any circular dependencies

---

## PHASE 2: DEPLOYMENT WAVE COMPUTATION

### Step 2A: Build Dependency Graph

```
For each ticket in sprint-hints.json:
  GRAPH[ticket_id] = ticket.dependencies

Represent as adjacency list:
  CLA-197 → []
  CLA-198 → [CLA-197]
  CLA-199 → [CLA-197]
  CLA-204 → [CLA-197, CLA-198, CLA-200, CLA-201, CLA-202, CLA-203]
  ...
```

### Step 2B: Cycle Detection

Run topological sort. If a cycle is detected, report the EXACT chain:

```
CRITICAL: Dependency cycle detected:
  CLA-201 → CLA-203 → CLA-204 → CLA-201

No valid deployment order exists. Fix dependencies in Linear
before running /sprint.
```

### Step 2C: Compute Waves

Group tickets into deployment waves based on dependencies:

```
Wave 1: [CLA-197]                          ← no dependencies
Wave 2: [CLA-198, CLA-199, CLA-200, ...]  ← depend on wave 1
Wave 3: [CLA-205, CLA-206]                ← depend on wave 2
Wave 4: [CLA-207]                          ← depend on wave 2
```

Verify computed waves match the `wave` field in sprint-hints.json.
Flag any mismatches as WARNING.

### Step 2D: Wave Statistics

```
┌────────┬────────┬─────────────────────────┬────────────────┐
│ Wave   │ Count  │ Tickets                 │ Parallelism    │
├────────┼────────┼─────────────────────────┼────────────────┤
│ 1      │ 3      │ CLA-197, CLA-198, ...   │ 3 concurrent   │
│ 2      │ 4      │ CLA-200, CLA-201, ...   │ 4 concurrent   │
│ 3      │ 2      │ CLA-205, CLA-206        │ 2 concurrent   │
│ 4      │ 1      │ CLA-207                 │ 1 (sequential) │
├────────┼────────┼─────────────────────────┼────────────────┤
│ TOTAL  │ 10     │                         │ max: 4         │
└────────┴────────┴─────────────────────────┴────────────────┘

Estimated agent windows: {total_tickets * 6-8} (Context + Worker + Verification + Review + Fix + Completion per ticket)
```

---

## PHASE 3: FILE CONFLICT ANALYSIS

### Step 3A: Build File Ownership Map

Extract `files_to_create` and `files_to_modify` from every ticket.
Build a map: `file_path → [ticket_ids]`.

### Step 3B: Compute CONFLICT_MATRIX

For each file touched by 2+ tickets:

```
┌─────────────────────────────────────────┬──────────┬───────────────────────────┐
│ File                                    │ Severity │ Tickets                   │
├─────────────────────────────────────────┼──────────┼───────────────────────────┤
│ src/components/copilot/types.ts         │ CRITICAL │ CLA-197 (create), CLA-198 │
│ package.json                            │ HIGH     │ CLA-197, CLA-205          │
│ src/App.tsx                             │ MEDIUM   │ CLA-205                   │
└─────────────────────────────────────────┴──────────┴───────────────────────────┘
```

Severity rules:
- **CRITICAL**: Two tickets both CREATE the same file
- **HIGH**: Two+ tickets MODIFY the same file AND are in the SAME wave (parallel execution)
- **MEDIUM**: Two+ tickets MODIFY the same file but in DIFFERENT waves (sequential, likely OK)
- **LOW**: One ticket creates, another modifies in a later wave (likely intentional)

### Step 3C: Verify Files Exist on Disk

For each `files_to_modify`:
```bash
test -f "{path}" && echo "EXISTS" || echo "MISSING"
```

If a file planned for modification doesn't exist → WARNING:
```
WARNING: {TICKET_ID} plans to modify {path}, but the file does not exist.
  Was it renamed or deleted since the plan was generated?
```

For each `files_to_create`:
```bash
test -f "{path}" && echo "ALREADY_EXISTS" || echo "OK"
```

If a file planned for creation already exists → WARNING:
```
WARNING: {TICKET_ID} plans to create {path}, but the file already exists.
  The worker may overwrite existing code.
```

### Step 3D: Ghost Dependency Detection

For each file in `files_to_modify`, grep for import statements that reference it:

```bash
# Find files that import from a modified file
grep -rl "from.*{module_path}" src/ --include="*.ts" --include="*.tsx" 2>/dev/null
```

If an importing file is NOT in any ticket's `files_to_create` or `files_to_modify` → flag:
```
WARNING (ghost dependency): {importer_path} imports from {modified_path}
  {modified_path} is being changed by {TICKET_ID}, but {importer_path}
  is not in any ticket. If the export signature changes, this will break.
```

---

## PHASE 4: INFRASTRUCTURE CHECKS

### Step 4A: Git State

```bash
# Check for clean working tree
git status --porcelain

# Check current branch
git branch --show-current

# Check if .claude/worktrees/ is gitignored
git check-ignore -q .claude/worktrees/ 2>/dev/null
```

Findings:
- Dirty working tree → WARNING: "Uncommitted changes may interfere with sprint"
- `.claude/worktrees/` not gitignored → HIGH: "Add .claude/worktrees/ to .gitignore before /sprint"

### Step 4B: Build Command Availability (NO EXECUTION)

Check that build commands exist — do NOT run them:

```bash
# Only check command existence, never execute
command -v npm >/dev/null 2>&1 && echo "npm: OK" || echo "npm: MISSING"

# Check package.json scripts exist
node -e "const p=require('./package.json'); console.log('build:', p.scripts?.build ? 'OK' : 'MISSING')"
node -e "const p=require('./package.json'); console.log('lint:', p.scripts?.lint ? 'OK' : 'MISSING')"
node -e "const p=require('./package.json'); console.log('test:run:', p.scripts?.['test:run'] ? 'OK' : 'MISSING')"
```

If sprint-config.yml exists, cross-reference its commands against package.json scripts.

### Step 4C: E2E Availability

```bash
command -v agent-browser >/dev/null 2>&1 && echo "agent-browser: OK" || echo "agent-browser: NOT INSTALLED (Phase 6 will be skipped)"
command -v npx >/dev/null 2>&1 && npx playwright --version 2>/dev/null && echo "playwright: OK" || echo "playwright: NOT INSTALLED"
```

### Step 4D: Worktree Readiness

```bash
# Check for stale worktrees from previous sprints
ls -la .claude/worktrees/ 2>/dev/null

# Check git worktree list for orphans
git worktree list
```

If stale worktrees exist → WARNING: "Stale worktrees from a previous sprint. Clean up with `git worktree prune`."

### Step 4E: Stale sprint-state.json Detection

```bash
cat ${PROBLEM_DIR}/sprint-state.json 2>/dev/null
```

If sprint-state.json exists AND `phase != "complete"`:
```
HIGH: Found ${PROBLEM_DIR}/sprint-state.json from sprint "{sprint_id}"
  Phase: {phase} — this sprint was interrupted.
  {tickets_complete}/{tickets_total} tickets were completed.

  Options:
    1. Run /sprint-resume to pick up where you left off
    2. Delete sprint-state.json and run /sprint for a fresh start
    3. Ignore and proceed (not recommended — may cause conflicts)
```

If sprint-state.json exists AND `phase == "complete"`:
```
INFO: Found completed sprint-state.json from sprint "{sprint_id}".
  This is safe to archive or delete.
```

### Step 4F: Failure Pattern Matching

```bash
cat .claude/failure-patterns.json 2>/dev/null
```

If failure-patterns.json exists, check for patterns matching the current ticket set:
- If a ticket modifies the same files as a previously-failed ticket → WARNING with the resolution pattern

---

## PHASE 5: REPORT GENERATION

### Step 5A: Assemble Report

```
═══════════════════════════════════════════════════════════════════
  SPRINT DRY-RUN REPORT
  Problem: {PROBLEM_ID}
  Generated: {ISO_TIMESTAMP}
  Plan commit: {plan_commit} ({FRESH|SLIGHTLY_STALE|STALE})
  Commits since plan: {COMMITS_SINCE}
═══════════════════════════════════════════════════════════════════

── 1. LINEAR RECONCILIATION ──────────────────────────────────────

{Reconciliation table from Phase 1}

Tickets matched: {N}/{total}
Mismatches: {N}
Orphans on Linear: {N}

── 2. DEPLOYMENT WAVES ───────────────────────────────────────────

{Wave table from Phase 2}

Total waves: {N}
Max parallelism: {N} concurrent agents
Estimated agent windows: {N}

── 3. FILE CONFLICT MATRIX ───────────────────────────────────────

{Conflict table from Phase 3}

CRITICAL conflicts: {N}
HIGH conflicts: {N}
Ghost dependencies: {N}

── 4. INFRASTRUCTURE ─────────────────────────────────────────────

Git state: {clean|dirty}
Branch: {branch}
Worktree .gitignore: {OK|MISSING}
Build commands: {OK|{list missing}}
E2E: {OK|NOT_INSTALLED}
Stale worktrees: {N}
Prior sprint state: {none|interrupted|completed}

── 5. COVERAGE PREVIEW ───────────────────────────────────────────

(Only shown if problem-statement.md exists)

{For each success criterion from problem-statement.md, list which
ticket(s) cover it, or flag UNCOVERED}

Success criteria covered: {N}/{total}
Uncovered criteria: {list}

═══════════════════════════════════════════════════════════════════
```

### Step 5B: Findings Summary (Grouped by Severity)

```
── FINDINGS ──────────────────────────────────────────────────────

CRITICAL ({N}):
  1. {finding}
  2. {finding}

HIGH ({N}):
  1. {finding}
  2. {finding}

WARNING ({N}):
  1. {finding}
  2. {finding}

INFO ({N}):
  1. {finding}
  2. {finding}
```

### Step 5C: Verdict

Based on findings, compute verdict:

```
VERDICT RULES:
  READY             → 0 CRITICAL, 0 HIGH
  READY_WITH_WARNINGS → 0 CRITICAL, ≤2 HIGH (with acceptable explanations)
  NOT_READY         → any CRITICAL, OR >2 HIGH
```

```
── VERDICT ───────────────────────────────────────────────────────

{READY | READY_WITH_WARNINGS | NOT_READY}

{If READY}:
  All checks passed. You can safely run /sprint.

{If READY_WITH_WARNINGS}:
  Sprint can proceed, but review the HIGH findings above.
  Consider fixing them first for a smoother run.

{If NOT_READY}:
  Sprint should NOT proceed until CRITICAL issues are resolved.
  {List specific actions to fix each CRITICAL finding}

═══════════════════════════════════════════════════════════════════
```

### Step 5D: Suggested Next Action

```
NEXT STEPS:
  {If READY}:       → Run /sprint to begin execution
  {If WARNINGS}:    → Fix warnings OR run /sprint with awareness
  {If NOT_READY}:   → {specific fix actions per CRITICAL finding}
  {If stale plan}:  → Re-run /tickets to refresh the plan
  {If interrupted}: → Run /sprint-resume to recover the prior sprint
```

---

## ORCHESTRATOR RULES

**RULE 1: READ-ONLY — CHANGE NOTHING**
This command does NOT create files, does NOT commit, does NOT modify sprint-state.json,
does NOT update Linear tickets, does NOT spawn worker agents. It is purely diagnostic.
The only outputs are text displayed to the user.

**RULE 2: HARD STOP ON MISSING sprint-hints.json**
If `${PROBLEM_DIR}/sprint-hints.json` does not exist, stop immediately. Do not attempt to
infer ticket information from Linear or other sources.

**RULE 3: REAL LINEAR API CALLS**
Use the actual Linear MCP to fetch ticket data. Do not assume tickets exist based
solely on sprint-hints.json. The whole point is to detect drift.

**RULE 4: NO BUILD EXECUTION**
Check that build commands EXIST (via `command -v` and package.json script keys).
NEVER execute `npm run build`, `npm run test`, or any build/test command. This
keeps the dry run fast and side-effect-free.

**RULE 5: PESSIMISTIC CONFLICT PREDICTION**
When computing file conflicts, assume the worst case. Two tickets modifying the
same file in the same wave = HIGH, even if they might touch different functions.
Better to over-warn than under-warn.

**RULE 6: PRECISE STALENESS MEASUREMENT**
Count exact commits since plan_commit. List the specific files that changed.
Cross-reference changed files against ticket file lists. "The plan is stale"
is not useful. "The plan is 3 commits stale and src/App.tsx was modified,
which CLA-205 plans to change" IS useful.

**RULE 7: GHOST DEPENDENCY DETECTION**
For each file being modified, grep for importers. If an importer is not in any
ticket's scope, flag it. This catches the #1 cause of post-merge breakage.

**RULE 8: WARN ABOUT /sprint-resume**
If a non-complete sprint-state.json exists, prominently suggest `/sprint-resume`
instead of `/sprint`. Users often don't realize a prior sprint was interrupted.

**RULE 9: NO AGENT SPAWNING**
The orchestrator does ALL analysis directly. Do not spawn Explore agents, Context
agents, or any subagents. This keeps the dry run fast and cheap.

**RULE 10: TITLE DRIFT DETECTION**
Compare ticket titles between sprint-hints.json and Linear using a similarity
threshold (>30% Levenshtein distance = drift). Titles often get edited on Linear
after `/tickets` runs, which can indicate scope changes.

**RULE 11: DEPENDENCY DIRECTION VALIDATION**
Dependencies must point from higher waves to lower waves. If a wave-1 ticket
depends on a wave-2 ticket, the wave assignment is wrong.

**RULE 12: ORPHAN DETECTION**
If Linear has tickets matching the sprint label that are NOT in sprint-hints.json,
flag them. These may have been manually created and should be included or excluded.

**RULE 13: VERDICT IS MECHANICAL**
The verdict (READY / READY_WITH_WARNINGS / NOT_READY) is computed from finding
counts, not subjective judgment. Zero CRITICAL + zero HIGH = READY. Period.

**RULE 14: ACTIONABLE FINDINGS**
Every finding must include a specific action to resolve it. "Ticket CLA-205
has a problem" is not actionable. "Ticket CLA-205 plans to modify src/App.tsx,
which was modified 2 commits ago — re-run /tickets to update the plan" IS actionable.

---

## FILE CONTRACT

### What /sprint-dry-run reads:
```
${PROBLEM_DIR}/sprint-hints.json          ← REQUIRED (from /tickets)
${PROBLEM_DIR}/problem-statement.md       ← OPTIONAL (from /define — enriches coverage preview)
.claude/sprint-config.yml          ← OPTIONAL (validates command config)
${PROBLEM_DIR}/sprint-state.json          ← OPTIONAL (detects interrupted sprints)
.claude/failure-patterns.json      ← OPTIONAL (matches known failure patterns)
```

### What /sprint-dry-run produces:
```
NOTHING. This command is read-only. Output is displayed to the user only.
```

### What /sprint-dry-run validates for /sprint:
```
- All tickets exist on Linear with expected statuses
- No dependency cycles
- File conflicts are identified and severity-rated
- Build infrastructure is available
- No stale sprint state from a prior crash
- Plan freshness relative to current codebase
- Ghost dependencies that could break post-merge
```

---

## EXECUTION CHECKLIST

```
[ ] Phase 0-Pre: Resolve Problem Directory
    [ ] Problem ID resolved (arg → active-problem → single dir → legacy → STOP)
    [ ] PROBLEM_DIR set to .claude/sprints/${PROBLEM_ID}
    [ ] Problem directory exists and contains sprint-hints.json

[ ] Phase 0: Preflight Validation
    [ ] sprint-hints.json located and parsed
    [ ] Schema validated (all required fields present)
    [ ] Optional inputs loaded (problem-statement.md, sprint-config.yml)
    [ ] Staleness computed (commits since plan_commit, changed files listed)
    [ ] Changed files cross-referenced against ticket file lists

[ ] Phase 1: Linear Reconciliation
    [ ] Linear MCP connectivity verified
    [ ] ALL tickets fetched from Linear (not just a sample)
    [ ] Reconciliation table built (hints vs Linear for every ticket)
    [ ] Mismatches flagged: missing, title drift, already Done, Cancelled
    [ ] Orphan tickets identified (on Linear but not in hints)
    [ ] Dependencies validated (exist, correct wave direction, no cycles in hints)

[ ] Phase 2: Deployment Wave Computation
    [ ] Dependency graph built from sprint-hints.json
    [ ] Topological sort completed (or cycle detected with exact chain)
    [ ] Waves computed and compared against hints wave fields
    [ ] Wave statistics table generated (count, tickets, parallelism)
    [ ] Agent window estimate calculated

[ ] Phase 3: File Conflict Analysis
    [ ] File ownership map built (file → [tickets])
    [ ] CONFLICT_MATRIX computed (CRITICAL/HIGH/MEDIUM/LOW)
    [ ] files_to_modify verified on disk (exist check)
    [ ] files_to_create verified on disk (not-already-exists check)
    [ ] Ghost dependencies detected (importers not in any ticket)

[ ] Phase 4: Infrastructure Checks
    [ ] Git state checked (clean/dirty, current branch)
    [ ] .claude/worktrees/ gitignore verified
    [ ] Build commands existence checked (NOT executed)
    [ ] E2E tool availability checked
    [ ] Stale worktrees detected
    [ ] sprint-state.json status checked
    [ ] Failure patterns loaded and matched (if available)

[ ] Phase 5: Report Generation
    [ ] Full report assembled (5 sections)
    [ ] Findings grouped by severity (CRITICAL > HIGH > WARNING > INFO)
    [ ] Verdict computed mechanically from finding counts
    [ ] Specific next actions suggested per finding
    [ ] Coverage preview included (if problem-statement.md exists)
```
