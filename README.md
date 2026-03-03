# Claude Sprint Orchestrator

A multi-agent sprint orchestration system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that turns Linear tickets into fully implemented, verified, and merged code, using Agent Teams (Context Agent + Worker Agent as live teammates) working in parallel isolated git worktrees.

> **Two slash commands. One pipeline.** `/tickets` plans your work. `/sprint` executes it.

---

## How It Works

The system is built around two Claude Code custom slash commands that form an end-to-end pipeline:

```
   Your idea
      │
      ▼
  /tickets "Build a notification system"
      │
      │  Analyzes codebase → generates plan → creates Linear tickets
      │  with edge cases, file context, caller-callee contracts,
      │  test patterns, and rollback plans
      │
      ▼
  /sprint
      │
      │  Fetches tickets → deploys Agent Teams per ticket →
      │  Context + Worker as live teammates → multi-layer verification →
      │  conflict-aware merging → E2E behavioral testing →
      │  auto-retrospective
      │
      ▼
   Merged, verified, tested code on your branch
```

---

## `/tickets` — From Idea to Linear Tickets

The planning command. Given a feature description, it analyzes your codebase, generates an implementation plan, breaks it into agent-sized tickets with rich context, and creates them on Linear.

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

1. **Pre-flight** — Validates Linear MCP, git state, baseline build. Loads sprint hints from /tickets (if available) for stale plan detection. User chooses coordination mode (Agent Teams recommended, Subagents fallback). Initializes sprint-state.json checkpoints
2. **Fetch tickets** — Queries Linear for matching tickets
3. **Deploy Agent Teams** — Per ticket: orchestrator (team lead) spawns Context Agent (Sonnet) + Worker Agent (Opus) as teammates in a shared worktree. They communicate directly, the Worker asks follow-up questions, the Context Agent reads files on demand
4. **Code simplifier** — Conditional refine pass (skipped in Agent Teams with clean code, for bug fixes, or small tickets). Auto-reverts if it breaks tests.
5. **Multi-layer verification loop** — Stale base check → Worker preflight validation → Context exhaustion detection → Evidence check → Mechanical verification (exit codes, test count > 0, config validation) → Edge case verification → Code review → Human review (optional) → Completion verdict → Orchestrator assembles raw proof and posts to Linear → Orchestrator marks Done and verifies
6. **Pre-merge integration check** — Merges ALL tickets into a temp branch and runs full test suite BEFORE real merges. Catches cross-ticket failures early. Routes failures back to the original Worker Agent (not a cold Build Gate Agent). Detects test fixture collisions across tickets.
7. **Merge scheduling** — Conflict prediction via file overlap analysis, intent context for resolution, dependency drift detection (fresh npm install after package.json changes), post-merge verification
8. **Build gate** — Full quality gate with bisection protocol for failure isolation
9. **E2E behavioral verification** — Per-ticket endpoint testing, DB state checks, integration verification
10. **Auto-retrospective** — Analyzes sprint performance, feeds learnings back to progress.txt and /tickets memory

### `/sprint` Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PHASE 0: PRE-FLIGHT                          │
│  Check Linear → Pull base → Build baseline → Tag snapshot           │
│  Choose coordination mode (Agent Teams recommended)                 │
│  Initialize sprint-state.json (checkpoint system)                    │
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
│  │  │  • Stay alive    │                     │  • Commit   │  │    │
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
│  L2: MECHANICAL VERIFICATION (exit codes, test count > 0, config)  │
│  L2.5: EDGE CASE VERIFICATION (grep tests for each case)          │
│  ⚡ CIRCUIT BREAKER: same error 2x → fresh agent or flag STUCK     │
│  L3: CODE REVIEW AGENT (security, logic, patterns)                 │
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
│         PHASE 6: E2E BEHAVIORAL VERIFICATION (PARALLEL)             │
│  One E2E agent per ticket: run tests + hit endpoints + check DB    │
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
| E2E Test Agent | Sonnet | Behavioral verification |
| Retrospective Agent | Sonnet | Post-sprint analysis + learning |

### Key Features

- **Agent Teams per ticket** — Context Agent (Sonnet) + Worker Agent (Opus) as live teammates in a shared worktree. The Worker asks follow-up questions, the Context Agent reads files on demand. No lossy context handoff. Agent Teams are restricted from touching Linear, only the independent verification chain handles ticket status.
- **Isolated git worktrees** — Each ticket team gets its own worktree via Claude Code's native worktree support
- **Circuit breaker** — Detects stuck agents (same error 2x), escalates to fresh agent or flags for manual intervention
- **Error classification** — Routes failures intelligently: rate limits → wait, missing files → re-context, type errors → code fix
- **Sprint-state.json checkpoints** — Persists state across context compaction events with recovery protocol
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
- **Sprint dashboard** — Live `.claude/sprint-dashboard.md` for observability
- **Post-sprint learning loop** — Auto-retrospective feeds learnings back to progress.txt, CLAUDE.md, and /tickets memory
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
cp .claude/commands/orchestrate-parallel-sprint.md your-project/.claude/commands/
cp .claude/commands/tickets.md your-project/.claude/commands/
```

```bash
# Option B: Clone and symlink
git clone https://github.com/rakeshutekar/claude-sprint-orchestrator.git
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

### Step 1: Generate Tickets

```
/tickets "Build a real-time notification system with WebSocket support,
          email fallback, and user preference management"
```

This will analyze your codebase, generate a plan, and after your approval, create tickets on Linear with full context.

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
E2E_CMD: "npx playwright test"
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
│   │   ├── orchestrate-parallel-sprint.md   # /sprint command (2250+ lines)
│   │   └── tickets.md                       # /tickets command (1100+ lines)
│   ├── worktrees/                           # Auto-created, must be in .gitignore
│   ├── sprint-state.json                    # Sprint checkpoint (auto-created)
│   ├── sprint-dashboard.md                  # Live status (auto-created)
│   ├── sprint-history/                      # Retrospective archive (auto-created)
│   │   └── sprint-{timestamp}.md
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
