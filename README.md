# Claude Sprint Orchestrator

A multi-agent sprint orchestration system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that turns ideas into fully implemented, verified, and merged code, using Agent Teams (Context Agent + Worker Agent as live teammates) working in parallel isolated git worktrees.

> **Three slash commands. One pipeline.** `/define` captures intent. `/tickets` plans your work. `/sprint` executes it.

---

## How It Works

The system is built around three Claude Code custom slash commands that form an end-to-end pipeline:

```
   Your idea
      │
      ▼
  /define
      │
      │  Quick codebase recon → structured dialogue (3-5 min) →
      │  problem statement with success criteria, user journey,
      │  testing strategy, and constraints
      │
      ▼
  /tickets "Build a notification system"
      │
      │  Reads problem statement → analyzes codebase → generates plan →
      │  creates Linear tickets with edge cases, file context,
      │  caller-callee contracts, test patterns, and rollback plans →
      │  validates all success criteria have ticket coverage
      │
      ▼
  /sprint
      │
      │  Reads problem statement → fetches tickets → deploys Agent Teams →
      │  Context + Worker as live teammates → multi-layer verification →
      │  conflict-aware merging → E2E behavioral testing (using user
      │  journey as test scenarios) → auto-retrospective
      │
      ▼
   Merged, verified, tested code on your branch
```

---

## `/define` — From Idea to Problem Statement

The intent capture command. Through a focused 3-5 minute dialogue (informed by a quick codebase scan), it produces a structured problem statement that becomes the contract for the entire pipeline.

### What It Does

1. **Quick codebase recon** (~10 seconds, silent) — Detects stack, test infrastructure, database/auth presence, and key directories. No agents, no deep reads — just enough to ask informed questions.
2. **Structured dialogue** (4-7 questions) — Asks one question at a time, adapting follow-ups based on codebase context and previous answers.
3. **Problem statement generation** — Produces `.claude/problem-statement.md` with problem description, user journey, success criteria, testing strategy, constraints, and codebase snapshot.
4. **Handoff** — Offers to launch `/tickets` immediately or save for later.

### Core Questions

| # | Question | Purpose | Always Asked? |
|---|----------|---------|---------------|
| Q1 | What problem are you solving? | Captures the *why*, not the *what* | Yes |
| Q2 | What does "done" look like? | User journey → E2E test scenarios + success criteria | Yes |
| Q3 | What level of testing? | Configures test expectations (adapts to existing test infra) | Yes |
| Q4 | Any constraints? | Libraries, deadlines, tech debt, external deps | Yes |
| Q5 | Database changes? | New tables vs extend existing (only if DB detected) | Conditional |
| Q6 | Auth/permissions? | Public vs authenticated vs role-based (only if auth detected) | Conditional |
| Q7 | External integrations? | Third-party APIs, webhooks, services | Conditional |

### How It Connects Downstream

The problem statement flows through the entire pipeline:

| Consumer | What It Uses | How |
|----------|-------------|-----|
| `/tickets` Explore Agent | Codebase snapshot + constraints | Focuses analysis on relevant areas, skips re-discovering stack basics |
| `/tickets` Approval Gate | Success criteria + implied features | Validates every criterion has at least one ticket covering it |
| `/sprint` Worker Agent | Constraints | Passed as hard constraints in Worker prompts |
| `/sprint` Completion Agent (L4) | Success criteria | Checks tickets against relevant criteria from the problem statement |
| `/sprint` E2E Test Agent (Phase 6) | User journey steps | Each step becomes an agent-browser verification scenario |
| `/sprint` Retrospective (Phase 8) | Full problem statement | Compares actual output against original intent |

### Key Design Decisions

- **Optional but recommended** — `/tickets` works without it; just prints a nudge: "Tip: Run `/define` first for better ticket quality"
- **Shallow recon only** — Reads manifest files and directory structure. No agents, no deep code analysis. That's `/tickets`' job.
- **One question at a time** — Conversation, not a form. Follow-ups adapt to answers.
- **Max 7 questions** — 3-5 minutes. Short enough that users won't skip it.

---

## `/tickets` — From Idea to Linear Tickets

The planning command. Given a feature description (enriched by `/define`'s problem statement if available), it analyzes your codebase, generates an implementation plan, breaks it into agent-sized tickets with rich context, and creates them on Linear.

### What It Does

1. **Broad codebase analysis** — An Explore agent maps your architecture, types, test infrastructure, and error patterns
2. **Plan generation** — Breaks the feature into dependency-ordered, agent-sized tickets
3. **Deep file context** — Parallel Context Agents do per-ticket deep reads (function signatures, caller analysis, ghost dependencies)
4. **Enrichment & validation** — Type-driven edge case generation, import graph dependency validation, complexity re-evaluation with auto-split, rollback plans for schema/migration tickets
5. **Approval gate** — Presents the full plan with edge case coverage, dependency validation, and complexity analysis
6. **Linear creation** — Creates a project with all tickets, dependencies, and labels

### `/tickets` Flow

```
/tickets "{FEATURE}"
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 0: PRE-FLIGHT                    │
│  ├── Check Linear MCP connection        │
│  ├── Verify git clean + pull base       │
│  ├── Verify baseline BUILD passes       │
│  └── Init support files (progress.txt,  │
│       agent-memory dir, .gitignore)     │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 1: BROAD CODEBASE ANALYSIS       │
│  ├── Explore Agent (Sonnet) — broad     │
│  │   ├── Architecture mapping           │
│  │   ├── Types & schemas (FULL defs)    │
│  │   ├── Test infrastructure            │
│  │   ├── Error patterns                 │
│  │   └── ANTI-HALLUCINATION enforced    │
│  ├── Step 1B: Validate unverified refs  │
│  └── Output: ARCHITECTURE_REPORT        │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 2: PLAN GENERATION               │
│  ├── Size tickets (per-ticket limits)   │
│  ├── Map dependencies                   │
│  ├── Tag tickets (migration/schema/etc) │
│  └── Output: Preliminary ticket list    │
│       (edge cases + context = "TBD")    │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 2.5: FILE-LEVEL CONTEXT AGENTS   │
│  ├── Parallel Context Agents (Sonnet)   │
│  │   ├── Deep file reads per ticket     │
│  │   ├── Function signatures + types    │
│  │   ├── Caller analysis (ghost deps)   │
│  │   ├── Error patterns per file        │
│  │   ├── Test patterns per module       │
│  │   └── Suggested edge cases           │
│  ├── Step 2.5B: Flag plan mismatches    │
│  │   └── Loop back to Phase 2 if needed │
│  └── Output: TICKET_CONTEXT_REPORT[]    │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 2.75: ENRICHMENT & VALIDATION    │
│  ├── 2.75A: Generate explicit edge cases│
│  │   └── Type-driven, ≥4 per ticket    │
│  ├── 2.75B: Validate dependencies       │
│  │   └── Import graph analysis          │
│  │   └── Circular dep detection         │
│  ├── 2.75C: Complexity re-evaluation    │
│  │   └── Auto-split oversized tickets   │
│  ├── 2.75D: Rollback plans              │
│  │   └── For schema/migration tickets   │
│  └── Output: Enriched ticket list       │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 3: APPROVAL GATE                 │
│  ├── Summary + ticket tree              │
│  ├── Edge case coverage count           │
│  ├── Dependency validation status       │
│  ├── Complexity changes summary         │
│  └── Options: create / modify / dry-run │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 4: CREATE ON LINEAR              │
│  ├── Create project                     │
│  ├── Create tickets (enriched template) │
│  ├── Set "blocked by" relationships     │
│  └── Add parent/child nesting           │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 5: SAVE & OUTPUT                 │
│  ├── Save plan to .claude/plans/        │
│  ├── Tag codebase snapshot (staleness)  │
│  ├── Display sprint config (all fields) │
│  ├── Save sprint hints (.json)          │
│  ├── Recommend coordination mode        │
│  ├── Update Explore agent memory        │
│  └── Offer to kick off /sprint          │
└─────────────────────────────────────────┘
```

### Key Features

- **Two-pass research** — Broad Explore sweep + per-ticket deep file reads for rich context
- **Type-driven edge case generation** — Mechanically derives edge cases from TypeScript interfaces/types (≥4 per ticket)
- **Import graph dependency validation** — Validates ticket dependencies against actual code imports, detects circular dependencies
- **Caller-callee contracts** — Prevents ghost dependencies and wrong-signature function calls
- **Complexity auto-split** — Re-evaluates ticket sizing and auto-splits oversized tickets
- **Rollback plans** — Auto-generated for schema/migration/integration tickets
- **Persistent Explore memory** — Codebase knowledge accumulates across `/tickets` runs
- **Anti-hallucination guardrails** — Every agent is required to show evidence with file paths and line numbers
- **Problem statement integration** — Reads `.claude/problem-statement.md` from `/define` if available. Enriches Explore Agent focus, validates all success criteria have ticket coverage at the Approval Gate, and passes constraints to Context Agents.
- **Baseline build verification** — Phase 0 verifies the base branch compiles before generating tickets
- **Sprint hints** — Saves ticket metadata (.claude/sprint-hints.json) for /sprint to pre-populate state and detect stale plans
- **Coordination mode recommendation** — Analyzes ticket complexity to recommend Agent Teams vs Subagents
- **Codebase snapshot tagging** — Tags the exact commit the plan was generated against for staleness detection
- **Partial creation rollback** — Tracks created ticket IDs for rollback if Linear API fails mid-creation
- **LINEAR MCP RESTRICTION on all agents** — Only the orchestrator touches Linear; read-only agents are explicitly restricted

### Enriched Ticket Template

Each ticket created on Linear includes:

| Section | Description |
|---------|-------------|
| **Description** | What to implement, scoped to one worktree |
| **Acceptance Criteria** | Explicit, testable requirements |
| **Edge Cases** | ≥4 type-driven edge cases (mandatory) |
| **Detailed File Context** | Function signatures, type definitions, callers |
| **Caller-Callee Contracts** | Exact signatures to match |
| **Test Patterns** | Existing test conventions with example structure |
| **Rollback Plan** | How to undo if it breaks (schema/migration tickets) |
| **Sizing** | S/M/L with estimated files and tests |

---

## `/sprint` — Parallel Agent Execution

The execution command. Fetches tickets from Linear, deploys Agent Teams per ticket (Context Agent + Worker Agent as live teammates in a shared worktree), runs multi-layer verification, merges with conflict prediction, and runs E2E behavioral testing.

### What It Does

1. **Context pre-flight** — Estimates remaining context window. If <60%, prompts user: Compact+Continue (saves state to `sprint-preflight.json`, compacts, resumes), Proceed as-is, or Cancel. Invisible when context is healthy.
2. **Pre-flight** — Validates Linear MCP, git state, baseline build. Loads sprint hints from /tickets (if available) for stale plan detection. Loads failure pattern database from previous sprints. User chooses coordination mode (Agent Teams recommended, Subagents fallback). Initializes sprint-state.json checkpoints
3. **Permission mode** — Prompts user to choose how to handle permission prompts: auto-approve sprint commands (recommended, generates allowedTools config), skip all permissions (autonomous mode), manual approval, or skip if pre-configured
4. **Fetch tickets** — Queries Linear for matching tickets
4. **Deploy Agent Teams** — Per ticket: orchestrator (team lead) spawns Context Agent (Sonnet) + Worker Agent (Opus) as teammates in a shared worktree. Context Agents write warm-start skeleton templates (imports, signatures, test scaffolding). Workers fill in business logic. Smart worktree strategy: dependency-aware branching pre-merges dep code for dependent tickets.
5. **Code simplifier** — Conditional refine pass (skipped in Agent Teams with clean code, for bug fixes, or small tickets). Auto-reverts if it breaks tests.
6. **Multi-layer verification loop** — Stale base check → Worker preflight validation → Context exhaustion detection → Evidence check → Parallel verification (Layers 2+3 run concurrently: mechanical verification + code review) → Edge case verification → Circuit breaker → Human review (optional) → Completion verdict → Orchestrator assembles raw proof and posts to Linear → Orchestrator marks Done and verifies. Cross-ticket learnings from completed tickets are fed into subsequent Workers.
7. **Pre-merge integration check** — Merges ALL tickets into a temp branch and runs full test suite BEFORE real merges. Catches cross-ticket failures early. Routes failures back to the original Worker Agent (not a cold Build Gate Agent). Detects test fixture collisions across tickets.
8. **Merge scheduling** — Conflict prediction via file overlap analysis, intent context for resolution, dependency drift detection (fresh npm install after package.json changes), post-merge verification
9. **Build gate** — Full quality gate with bisection protocol for failure isolation
10. **E2E behavioral verification** — Uses Vercel's `agent-browser` CLI for browser interactions. Orchestrator starts one shared dev server. Each E2E agent runs in isolated `--session {TICKET_ID}`. Snapshot → interact via @refs → verify behaviors → collect evidence.
11. **Auto-retrospective** — Analyzes sprint performance, updates failure pattern database, feeds learnings back to progress.txt and /tickets memory

### `/sprint` Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                  STEP 0-PRE: CONTEXT PRE-FLIGHT                     │
│  Estimate remaining context window                                  │
│  If <60%: prompt user → [Compact+Continue / Proceed / Cancel]       │
│  Compact: save state to sprint-preflight.json → compact → reload    │
│  If ≥60%: skip silently                                             │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        PHASE 0: PRE-FLIGHT                          │
│  Check Linear → Pull base → Build baseline → Tag snapshot           │
│  Load failure patterns + sprint hints                               │
│  Choose coordination mode (Agent Teams recommended)                 │
│  Initialize sprint-state.json (checkpoint system)                    │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 STEP 0J: PERMISSION MODE SELECTION                   │
│  [Auto-approve / Skip all / Manual / Pre-configured]                │
│  Auto-approve: generates allowedTools config from sprint commands    │
│  Skip all: verifies --dangerously-skip-permissions flag             │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PHASE 1: FETCH TICKETS                           │
│  Query Linear for all tickets matching LINEAR_FILTER                │
│  Store: [{id, title, description, priority, labels}]                │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼     (one Agent Team per ticket)
┌──────────────────────────────────────────────────────────────────┐
│           PHASE 2: DEPLOY AGENT TEAMS (PARALLEL)                 │
│                                                                  │
│  Smart worktree strategy: dependency-aware branching             │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  PER TICKET — SHARED WORKTREE (Agent Team)               │    │
│  │                                                          │    │
│  │  ┌─────────────────┐  ◄── messages ──►  ┌────────────┐  │    │
│  │  │  CONTEXT AGENT   │   (real-time)      │  WORKER    │  │    │
│  │  │  (Sonnet 4.6)   │                     │  (Opus 4.6)│  │    │
│  │  │                 │  W: "signature?"    │            │  │    │
│  │  │  • Read codebase │  C: "fn(x:T):R"   │  • Implement│  │    │
│  │  │  • Map patterns  │  W: "test mock?"   │  • Write tests│ │    │
│  │  │  • Answer Qs     │  C: "vi.mock(...)" │  • Lint/type│  │    │
│  │  │  • Warm-start    │                     │  • Commit   │  │    │
│  │  │    templates     │                     │            │  │    │
│  │  └─────────────────┘                     └────────────┘  │    │
│  │                                                          │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│    PHASE 2.5: CODE SIMPLIFIER (conditional, non-blocking)          │
│    Skip: Agent Teams + clean code, bug fixes, small tickets        │
│    Run: subagents mode, 5+ files. Auto-revert if tests break.     │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│       PHASE 3: VERIFICATION LOOP (PER TICKET)                      │
│                                                                     │
│  Pre: STALE BASE CHECK (rebase if base branch moved)               │
│  L0.5: PREFLIGHT CHECK (did worker run all 4 commands?)            │
│  L0.7: CONTEXT EXHAUSTION CHECK (truncated output → fresh Worker)  │
│  L1: EVIDENCE CHECK (orchestrator — no agent)                      │
│  L2+L3: PARALLEL VERIFICATION                                     │
│    L2: MECHANICAL (exit codes, test count > 0, config)             │
│    L3: CODE REVIEW (security, logic, patterns)                     │
│  L2.5: EDGE CASE VERIFICATION (grep tests for each case)          │
│  ⚡ CIRCUIT BREAKER: same error 2x → fresh agent or flag STUCK     │
│  L3.5: HUMAN REVIEW (optional, if HUMAN_IN_LOOP=true)             │
│  L4: COMPLETION AGENT (verdict only, no Linear access)             │
│  L5: ORCHESTRATOR POSTS PROOF (raw terminal output to Linear)      │
│  L5.5: ORCHESTRATOR MARKS DONE (sets + verifies on Linear)         │
│                                                                     │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│              PHASE 4: MERGE SCHEDULING                              │
│  Scheduler Agent: conflict prediction + merge ordering              │
│  Conflict Agent: resolves with intent context + edge cases          │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│         PHASE 4.5: PRE-MERGE INTEGRATION CHECK                     │
│  Temp branch → merge ALL tickets → npm install → full test suite   │
│  Test fixture collision detection across tickets                   │
│  FAIL → isolate culprit → route to ORIGINAL Worker Agent           │
│  PASS → proceed to real merges with confidence                     │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│         PHASE 4 (cont): MERGE EXECUTOR                             │
│  Sequential merges with pre-merge tags + dependency drift checks   │
│  Post-merge verification: both tickets' tests must pass            │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│              PHASE 5: BUILD GATE (with Bisection)                   │
│  Build + Lint + Typecheck + Unit tests — must all pass              │
│  If fail → BISECT using pre-merge tags → isolate culprit            │
│  Fix culprit or revert (PARTIAL_MERGE) → continue                  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│     PHASE 6: E2E BEHAVIORAL VERIFICATION (agent-browser, PARALLEL)  │
│  Orchestrator starts ONE shared dev server                          │
│  One E2E agent per ticket (--session {TICKET_ID} isolation):        │
│  agent-browser snapshot → interact via @refs → verify behaviors     │
│  Failure → create Linear ticket with evidence                       │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│              PHASE 7: REMAINING TICKET CHECK (LOOP)                 │
│  If tickets remain → loop back to Phase 2                          │
│  Safety: MAX_LOOP_ITERATIONS cap                                    │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│         PHASE 8: POST-SPRINT LEARNING LOOP                          │
│  Retrospective Agent: analyze sprint performance                   │
│  Update progress.txt, suggest CLAUDE.md changes                    │
│  Update failure pattern database (.claude/failure-patterns.json)   │
│  Feed learnings back to /tickets memory                            │
│  Save to .claude/sprint-history/                                   │
└─────────────────────────────────────────────────────────────────────┘
```

### Agent Inventory

| Agent | Model | Purpose |
|-------|-------|---------|
| Context Agent | Sonnet | Codebase research + live follow-up answers (teammate) |
| Worker Agent | Opus | Implementation + edge cases + evidence (teammate) |
| Fresh Worker Agent | Opus | Circuit breaker escalation — clean context |
| Code Simplifier | Opus | Refine code clarity (non-blocking) |
| Verification Agent | Sonnet | Independent verification + cross-check |
| Code Review Agent | Sonnet | Security, logic, patterns |
| Fix Agent | Opus | Fix verification/review/human issues |
| Completion Agent | Sonnet | Requirement matching verdict only (no Linear access) |
| Scheduler Agent | Sonnet | Conflict prediction + merge ordering |
| Conflict Agent | Opus | Resolve merges with intent context |
| Build Gate Agent | Opus | Fix build failures (after bisection) |
| E2E Test Agent | Sonnet | Behavioral verification via agent-browser CLI |
| Retrospective Agent | Sonnet | Post-sprint analysis + learning |

### Key Features

- **Context pre-flight check** — Estimates remaining context before sprint start. If <60%, prompts user: Compact+Continue (saves all parsed state to `sprint-preflight.json`, compacts, reloads seamlessly), Proceed as-is, or Cancel. Invisible when context is healthy.
- **Permission mode selection** — Before spawning agents, prompts user to choose: auto-approve sprint commands (generates precise `allowedTools` config from your BUILD_CMD/LINT_CMD/TEST_CMD), skip all permissions (`--dangerously-skip-permissions`), manual approval, or skip if already configured. Eliminates hundreds of "Allow?" prompts during sprint execution.
- **Agent Teams per ticket** — Context Agent (Sonnet) + Worker Agent (Opus) as live teammates in a shared worktree. The Worker asks follow-up questions, the Context Agent reads files on demand. No lossy context handoff. Agent Teams are restricted from touching Linear, only the independent verification chain handles ticket status.
- **Warm-start skeleton templates** — Context Agents write actual skeleton files (correct imports, function signatures, type definitions, test scaffolding) in the worktree. Workers fill in business logic instead of starting from blank files.
- **Smart worktree strategy** — Dependency-aware branching: dependent tickets get worktrees with dependency code pre-merged. Wave-based deployment order ensures deps complete before dependents.
- **Isolated git worktrees** — Each ticket team gets its own worktree via Claude Code's native worktree support
- **Cross-ticket learning** — INTRA_SPRINT_LEARNINGS buffer captures error resolutions after each ticket passes verification. Subsequent Workers receive these discoveries, avoiding redundant failures.
- **Parallel verification (Layers 2+3)** — Mechanical verification and code review run concurrently instead of sequentially. Combined feedback on failure avoids 2 round trips.
- **Circuit breaker** — Detects stuck agents (same error 2x), escalates to fresh agent or flags for manual intervention
- **Error classification** — Routes failures intelligently: rate limits → wait, missing files → re-context, type errors → code fix
- **Failure pattern database** — `.claude/failure-patterns.json` persists error→resolution mappings across sprints. High-frequency patterns (≥3 occurrences) are pre-injected into Worker prompts as warnings.
- **Sprint-state.json checkpoints** — Persists state across context compaction events with recovery protocol
- **Orchestrator self-health monitoring** — Checks context health at 70% threshold. Writes ALL state to durable storage. Detects degradation signals (forgetting tickets, losing agent IDs). Reloads from disk if degraded.
- **Conflict prediction** — Scheduler Agent builds a CONFLICT_MATRIX from file overlap analysis before merging
- **Intent-aware conflict resolution** — Conflict Agent receives WHY each side changed shared files + both tickets' edge cases
- **Bisection protocol** — Binary search using pre-merge tags to isolate which merge broke the build
- **Partial merge / graceful degradation** — Ships completed tickets even when some are stuck
- **Edge case verification** — Layer 2.5 greps test files for every edge case from the ticket description
- **Worker preflight checklist** — Workers must run all 4 quality commands and verify exit codes before returning. Rejected immediately if preflight not run.
- **Mechanical verification** — Verification Agent checks exit codes (not interpretations), asserts test count > 0, validates project config for hidden permissiveness (skipLibCheck, silenced lint rules)
- **Pre-merge integration check** — All tickets merged into a temp branch and tested together BEFORE real merges. Catches cross-ticket semantic conflicts. Routes failures back to the original Worker Agent (who has context), not a cold Build Gate Agent. Detects test fixture collisions across tickets.
- **Stale base detection** — Rebases worktrees if base branch moved during sprint, preventing "passed against old code" failures
- **Dependency drift detection** — Fresh npm install after any ticket that modifies package.json or lock files
- **Code Simplifier safeguards** — Conditional execution (skipped in Agent Teams + clean code, bug fixes, small tickets). Auto-reverts if it breaks tests.
- **Context exhaustion detection** — Detects truncated or degraded Worker output and spawns a fresh agent with partial work. In Agent Teams mode, the Context Agent self-monitors for degradation and warns the Worker. The Worker verifies Context Agent answers by reading files directly when warnings appear.
- **Crash recovery with rollback safety** — After compaction or crash, reconciles sprint-state.json against actual Linear state. Detects and repairs four inconsistency types: phantom completes, orphaned evidence comments, missing status changes, and stale in-progress states.
- **E2E via agent-browser** — Uses Vercel's agent-browser CLI for browser-based verification. Lightweight @ref snapshots keep context usage minimal. `--session {TICKET_ID}` for parallel isolation.
- **Sprint dashboard** — Live `.claude/sprint-dashboard.md` for observability
- **Post-sprint learning loop** — Auto-retrospective feeds learnings back to progress.txt, CLAUDE.md, /tickets memory, and failure pattern database
- **Human-in-loop mode** — Optional pause for human review before marking tickets Done
- **Coordination mode choice** — Agent Teams by default, Subagents as lower-cost fallback

---

## Guardrails

Both commands share a philosophy of **evidence before assertion**:

### Verification Philosophy (6 Rules)

1. **No completion claims without fresh verification evidence** — "Should work" is not evidence
2. **Errors are caught at write-time, not review-time** — Backpressure pattern
3. **Learnings accumulate across agents** — Ralph Pattern via progress.txt
4. **Zero tolerance for fake work** — Never fabricate, approximate, or reconstruct output
5. **Communicate problems, don't hide them** — Honest failure reports over fake success
6. **Edge cases are not optional** — Every function tested with null, empty, boundary values

### Anti-Hallucination Rules

Injected into every agent prompt:

- **Show your work** — Every claim includes terminal output or file paths as proof
- **Never fabricate output** — If you didn't run it, you can't quote it
- **Admit uncertainty** — "I am not certain because [reason]"
- **No silent workarounds** — Report problems, don't hide them
- **Strict evidence format** — COMMAND → EXIT_CODE → OUTPUT → VERDICT
- **Compaction safety** — Re-run verification after context compaction

### Trust Boundary: Only the Orchestrator Touches Linear

The system enforces a strict rule: **no agent interacts with Linear**. Only the orchestrator does.

- **Collaborators** (Agent Team: Context Agent + Worker Agent) — implement the ticket in a shared worktree. Restricted from Linear MCP.
- **Auditors** (Verification Agent, Code Review Agent, Completion Agent) — run as independent subagents. Also restricted from Linear MCP. They return structured results to the orchestrator.
- **Orchestrator** (Layer 5, 5.5) — assembles raw terminal output from Verification and Code Review agents, adds the Completion Agent's requirement table, and posts the evidence comment to Linear directly. Then marks the ticket Done and verifies.

Raw terminal output IS proof. Agent-written summaries are NOT proof. The orchestrator captures what the agents actually ran (build output, test output, lint output) and posts that as evidence, not a summary an agent wrote about it.

---

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (v2.1.49+ for native worktree support)
- [Linear MCP](https://github.com/anthropics/linear-mcp) connected and authenticated
- A git repository with a working build/test pipeline

### Setup

1. Clone this repo or copy the commands into your project:

```bash
# Option A: Copy commands directly into your project
mkdir -p your-project/.claude/commands
cp .claude/commands/define-problem.md your-project/.claude/commands/
cp .claude/commands/orchestrate-parallel-sprint.md your-project/.claude/commands/
cp .claude/commands/tickets.md your-project/.claude/commands/
```

```bash
# Option B: Clone and symlink
git clone https://github.com/rakeshutekar/claude-sprint-orchestrator.git
ln -s $(pwd)/claude-sprint-orchestrator/.claude/commands/define-problem.md your-project/.claude/commands/
ln -s $(pwd)/claude-sprint-orchestrator/.claude/commands/orchestrate-parallel-sprint.md your-project/.claude/commands/
ln -s $(pwd)/claude-sprint-orchestrator/.claude/commands/tickets.md your-project/.claude/commands/
```

2. Ensure Linear MCP is connected in Claude Code:
```bash
# In Claude Code, run:
/mcp
# Select the Linear server and complete OAuth
```

3. Verify `.claude/worktrees/` is in your `.gitignore`:
```bash
echo ".claude/worktrees/" >> .gitignore
```

---

## Usage

### Step 0: Define the Problem (Recommended)

```
/define
```

This starts a 3-5 minute structured dialogue. It scans your codebase (quick recon), then asks 4-7 focused questions about what you're building, what "done" looks like, and how you want it tested. Produces `.claude/problem-statement.md`.

### Step 1: Generate Tickets

```
/tickets "Build a real-time notification system with WebSocket support,
          email fallback, and user preference management"
```

This will analyze your codebase (using the problem statement for focus if available), generate a plan, validate all success criteria have ticket coverage, and after your approval, create tickets on Linear with full context.

### Step 2: Run the Sprint

Copy the sprint config output from `/tickets` and run:

```
/sprint

## Sprint Config

BRANCH_BASE: develop
LINEAR_FILTER:
  team: "ENG"
  label: "sprint-notifications"
  status: ["Todo", "In Progress"]
PROJECT_STANDARDS: "CLAUDE.md"
BUILD_CMD: "npm run build"
LINT_CMD: "npm run lint"
TEST_CMD: "npm run test:run"
TYPECHECK_CMD: "npx tsc --noEmit"
E2E_CMD: "agent-browser"
MAX_LOOP_ITERATIONS: 3
HUMAN_IN_LOOP: false
PARTIAL_MERGE: true
SPRINT_DASHBOARD: true

Now execute the orchestration.
```

### Configuration Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `BRANCH_BASE` | Yes | — | Base branch to work from |
| `LINEAR_FILTER.team` | Yes | — | Linear team key |
| `LINEAR_FILTER.label` | No | — | Label filter for tickets |
| `LINEAR_FILTER.status` | Yes | — | Statuses to pick up |
| `PROJECT_STANDARDS` | Yes | — | Path to project standards (e.g., CLAUDE.md) |
| `BUILD_CMD` | Yes | — | Build command |
| `LINT_CMD` | Yes | — | Lint command |
| `TEST_CMD` | Yes | — | Unit test command |
| `TYPECHECK_CMD` | No | — | TypeScript type check command |
| `E2E_CMD` | No | — | E2E test command |
| `COMMIT_PREFIX` | No | `feat` | Conventional commit prefix |
| `MAX_LOOP_ITERATIONS` | No | `3` | Safety cap on fix-up loops per ticket |
| `HUMAN_IN_LOOP` | No | `false` | Pause for human review before marking Done |
| `PARTIAL_MERGE` | No | `true` | Merge completed tickets even if some are stuck |
| `SPRINT_DASHBOARD` | No | `true` | Write live sprint-dashboard.md |

---

## Coordination Modes

At sprint start, you choose between two coordination modes:

### Agent Teams (Recommended)

Per ticket, the orchestrator (team lead) spawns a Context Agent (Sonnet) and Worker Agent (Opus) as teammates in the same worktree. Both agents are alive simultaneously and communicate directly.

- The Worker can ASK the Context Agent for exact function signatures, test patterns, error handling conventions in real-time
- No lossy context transfer. The Context Agent stays alive with full codebase knowledge
- Reduces verification loop iterations because the Worker gets better information upfront
- Higher token cost (Context Agent stays alive during implementation) but fewer retries
- Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

### Subagents (Fallback, lower cost)

Each agent runs independently. The orchestrator passes all context between them as a one-way handoff. The Context Agent runs first, returns a text summary, and dies. The Worker receives that static summary in its prompt and cannot ask follow-up questions.

- Lower token cost (~$2-5 per ticket)
- Predictable, sequential flow
- Works with any Claude Code version
- Best when you want to minimize token spend on simple, well-defined tickets

---

## File Structure

```
your-project/
├── .claude/
│   ├── commands/
│   │   ├── define-problem.md                # /define command (~600 lines)
│   │   ├── orchestrate-parallel-sprint.md   # /sprint command (4600+ lines)
│   │   └── tickets.md                       # /tickets command (1800+ lines)
│   ├── worktrees/                           # Auto-created, must be in .gitignore
│   ├── problem-statement.md                 # From /define — intent contract (auto-created)
│   ├── sprint-state.json                    # Sprint checkpoint (auto-created)
│   ├── sprint-preflight.json                # Context pre-flight checkpoint (temporary)
│   ├── sprint-dashboard.md                  # Live status (auto-created)
│   ├── sprint-history/                      # Retrospective archive (auto-created)
│   │   └── sprint-{timestamp}.md
│   ├── failure-patterns.json                # Cross-sprint error→resolution DB
│   ├── plans/                               # Saved ticket plans (auto-created)
│   └── agent-memory/
│       └── tickets-explore/                 # Persistent Explore agent memory
├── progress.txt                             # Shared memory across agents (Ralph Pattern)
└── .gitignore                               # Must include .claude/worktrees/
```

---

## Cost & Token Warning

> **This system is designed for serious feature development and will consume significant tokens.**

### Estimated Costs Per Sprint

| Sprint Size | Tickets | Estimated Cost | Context Windows |
|------------|---------|----------------|-----------------|
| Small | 2-3 tickets | $5-15 | ~10-20 agent windows |
| Medium | 4-6 tickets | $15-40 | ~25-50 agent windows |
| Large | 7-10 tickets | $40-80+ | ~50-100+ agent windows |

### Why It Uses So Many Tokens

Each ticket spawns **multiple agents** across the pipeline:

- 1 Context Agent (Sonnet) — codebase research
- 1 Worker Agent (Opus) — implementation
- 1 Code Simplifier (Opus) — optional refine
- 1+ Verification Agent (Sonnet) — independent verification
- 1+ Code Review Agent (Sonnet) — security/quality check
- 0-N Fix Agents (Opus) — if issues found
- 1 Completion Agent (Sonnet) — requirement matching verdict (no Linear access)
- 1 E2E Test Agent (Sonnet) — behavioral verification

Plus global agents: Scheduler, Conflict Resolution, Build Gate, Retrospective.

**A 5-ticket sprint could easily spawn 40-60 agent context windows.**

### Tips to Manage Cost

1. **Start small** — Run with 2-3 tickets first to calibrate
2. **Use `HUMAN_IN_LOOP: true`** — Review each ticket before it consumes more loops
3. **Set `MAX_LOOP_ITERATIONS: 2`** — Lower the retry cap
4. **Use Subagents mode** — Lower cost than Agent Teams
5. **Check the sprint dashboard** — Monitor `.claude/sprint-dashboard.md` to catch issues early
6. **Use `/tickets` dry-run** — Review the plan before committing to a full sprint

---

## Requirements

- **Claude Code v2.1.49+** — for native git worktree support
- **Claude API access** — with Opus 4.6 and Sonnet 4.6 models
- **Linear account** — with Linear MCP connected in Claude Code
- **A buildable project** — with working build, lint, typecheck, and test commands
- **Git repository** — clean working tree on the base branch
- **agent-browser** (optional) — Vercel's agent-browser CLI for E2E behavioral verification. If not installed, Phase 6 is skipped (non-blocking). Install: `npm install -g agent-browser`

---

## License

MIT

---

## Contributing

Contributions are welcome! If you have ideas for improving the orchestration flow, adding new verification layers, or optimizing token usage, please open an issue or PR.

---

## Acknowledgments

Built with patterns inspired by:

- **Ralph Loop** — Shared memory across agents via progress.txt
- **Backpressure Pattern** — Errors caught at write-time, not review-time
- **Evidence-Based Completion** — No claims without proof
- **Circuit Breaker Pattern** — Detect and escalate stuck loops
- **Bisection Protocol** — Binary search for build failure isolation
