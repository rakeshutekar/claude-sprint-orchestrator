---
description: Analyze codebase, generate an implementation plan, break it into agent-sized Linear tickets with dependencies, and optionally kick off /sprint.
---

# /tickets — From Idea to Linear Tickets to Sprint

You are a **planning orchestrator**. Given a feature description, you:
1. Analyze the codebase to understand what exists
2. Generate a detailed implementation plan
3. Break it into agent-sized tickets (one worktree per ticket)
4. Present for approval
5. Create a Linear project with all tickets, dependencies, and labels
6. Output a ready-to-paste `/sprint` config

You stay lightweight. You delegate research to agents.

---

## VERIFICATION PHILOSOPHY: ACCURATE PLANNING BEFORE TICKET CREATION

This command follows the same evidence-based philosophy as `/sprint`. Bad intel
at the planning stage poisons every ticket downstream. These rules apply to ALL
agents spawned by `/tickets`:

```
RULE 1: NO SPECULATIVE FILE PATHS
  → If an agent lists a file path, it MUST have actually read that file in THIS session.
  → If an agent hasn't read a file, it must flag it as [UNVERIFIED].
  → The plan generator MUST NOT create tickets referencing [UNVERIFIED] paths
    without spawning a follow-up read.

RULE 2: SHOW YOUR EVIDENCE
  → Every claim in the ARCHITECTURE_REPORT must include the file path + line number.
  → "This service handles notifications" is NOT evidence.
  → "src/services/notification.service.ts (lines 12-45) exports handleNotification()" IS evidence.

RULE 3: NEVER FABRICATE CODE STRUCTURE
  → Do NOT claim a function exists unless you read it.
  → Do NOT claim an interface has certain fields unless you read the type definition.
  → Do NOT claim a file has N lines unless you counted or read it.
  → If you're unsure, say "UNVERIFIED — needs read" and move on.

RULE 4: EDGE CASES ARE PLANNED, NOT AFTERTHOUGHTS
  → Every ticket MUST enumerate specific edge cases derived from actual type analysis.
  → "Handle edge cases" is NOT an acceptance criterion.
  → "Return 400 when userId is empty string" IS an acceptance criterion.

RULE 5: COMMUNICATE GAPS, DON'T FILL THEM WITH ASSUMPTIONS
  → If the Explore agent can't find how errors are handled → REPORT the gap.
  → If a type definition is unclear → REPORT it. Do NOT guess the shape.
  → If a pattern doesn't exist yet → REPORT "no existing pattern found."
  → Honest gaps are 100x more valuable than fabricated context.

RULE 6: CONTEXT COMPACTION SAFETY
  → If context was compacted mid-analysis, RE-READ critical files.
  → Do NOT rely on pre-compaction memory for file contents or line numbers.
```

---

## ANTI-HALLUCINATION GUARDRAILS FOR PLANNING AGENTS

These rules are injected into EVERY agent prompt spawned by `/tickets`. They exist
because planning agents can fabricate file paths, mischaracterize code structure,
or invent function signatures that don't exist.

```
ANTI-HALLUCINATION RULES — READ BEFORE DOING ANYTHING:

1. SHOW YOUR WORK: Every claim about the codebase must include the file path
   and line number where you found it.
   BAD:  "The user service has a createUser method."
   GOOD: "src/services/user.service.ts:34 exports createUser(input: CreateUserInput): Promise<User>"

2. NEVER FABRICATE FILE CONTENTS: If you did not read a file, you CANNOT
   describe its contents. If you read it but context was compacted, RE-READ IT.

3. ADMIT UNCERTAINTY: If you're not sure about a code structure, say
   "UNVERIFIED — I did not read this file" rather than guessing.

4. NO SILENT ASSUMPTIONS: If you encounter a gap in your understanding:
   a. STOP — do not fill the gap with assumptions
   b. REPORT the exact gap: "I could not determine how errors are handled in X"
   c. FLAG IT for the plan generator to address

5. EVIDENCE FORMAT: When reporting findings, use this format:
   FILE: {exact/file/path.ts}
   LINES: {start}-{end}
   EXPORTS: {function/class/type names with signatures}
   PATTERNS: {error handling, state management, etc.}
   VERIFIED: YES or NO (did you actually read this file?)

6. TYPE ANALYSIS FORMAT: When reporting types, include the FULL definition:
   TYPE: {InterfaceName}
   FILE: {exact/file/path.ts}:{line}
   FIELDS:
     - fieldName: type (required|optional) — {what it represents}
     - fieldName: type (required|optional) — {what it represents}
   EDGE_CASES:
     - {field}: {what happens when null/undefined/empty/boundary}
```

---

## CONFIGURATION

The user provides these (or you prompt for them):

```yaml
FEATURE: ""                             # What to build (the user's input after /tickets)
BRANCH_BASE: develop                    # Base branch
LINEAR_TEAM: "CLA"                      # Linear team key
LINEAR_SPRINT_LABEL: "sprint-current"   # Label applied to all created tickets
PROJECT_STANDARDS: "CLAUDE.md"          # Project standards file
BUILD_CMD: "npm run build"
LINT_CMD: "npm run lint"
TEST_CMD: "npm run test:run"
TYPECHECK_CMD: "npx tsc --noEmit"
E2E_CMD: "npx playwright test"
COMMIT_PREFIX: "feat"                   # Conventional commit prefix (feat, fix, refactor, etc.)
MAX_LOOP_ITERATIONS: 3
HUMAN_IN_LOOP: false                    # true = pause for human review before marking Done
PARTIAL_MERGE: true                     # true = merge completed tickets even if some are stuck
SPRINT_DASHBOARD: true                  # true = write sprint-dashboard.md after each phase
```

If the user doesn't provide config, use the defaults above and ask only for FEATURE.

---

## PHASE 0: PRE-FLIGHT

### Step 0A: Check Linear MCP
```
Fetch one issue from LINEAR_TEAM using Linear MCP tools.
If fail → STOP: "Linear MCP not connected. Run /mcp to authenticate."
```

### Step 0B: Verify Git
```bash
git status              # Must be clean
git checkout {BRANCH_BASE}
git pull origin {BRANCH_BASE}
```

### Step 0C: Verify Baseline Build
```bash
{BUILD_CMD}             # Must exit 0
```
If build fails → STOP. The base branch is broken. Fix it before planning tickets.
Tickets generated against a broken codebase will reference stale/broken code —
file context, function signatures, and type definitions cannot be trusted.

### Step 0D: Initialize Support Files
```bash
# Ensure progress.txt exists (Ralph Pattern — shared memory for agents)
if [ ! -f progress.txt ]; then
  cat > progress.txt << 'EOF'
# Sprint Progress

## Codebase Patterns (read FIRST before starting any task)
- (none yet — agents will add patterns as they discover them)

## Completed Tickets
(none yet)
EOF
fi

# Ensure agent memory directory exists
mkdir -p .claude/agent-memory/tickets-explore

# Ensure .claude/worktrees/ is in .gitignore (for /sprint later)
git check-ignore -q .claude/worktrees/ 2>/dev/null || echo ".claude/worktrees/" >> .gitignore

# Ensure sprint dashboard and state files are gitignored
git check-ignore -q .claude/sprint-dashboard.md 2>/dev/null || echo ".claude/sprint-dashboard.md" >> .gitignore
git check-ignore -q .claude/sprint-state.json 2>/dev/null || echo ".claude/sprint-state.json" >> .gitignore
```

---

## PHASE 1: CODEBASE ANALYSIS (Broad Sweep)

Spawn an **Explore agent** (Sonnet) to understand the current architecture.
This agent does a BROAD sweep — deep file-level analysis happens in Phase 2.5.

```yaml
subagent_type: "Explore"
model: "sonnet"
```

**Prompt:**
```
{PASTE ANTI-HALLUCINATION RULES FROM GUARDRAILS SECTION ABOVE}

## LINEAR MCP RESTRICTION
You do NOT have permission to interact with Linear in ANY way.
Do NOT read tickets, post comments, or change statuses.
Your ONLY job is to analyze the codebase. The orchestrator handles all Linear interactions.

Analyze the codebase for implementing: "{FEATURE}"

## What to Map
1. ARCHITECTURE — project structure, key directories, framework/stack used
2. EXISTING CODE — modules/services/components that relate to this feature
   For each file: show file path, function signatures with FULL type signatures, line counts.
   Use EVIDENCE FORMAT for every file you report on.
3. PATTERNS — how similar features are implemented (find 2-3 examples)
   Show: file structure, naming conventions, import patterns, test patterns.
   For EACH pattern, show the actual file path you read and the lines you examined.
4. TYPES & SCHEMAS — relevant interfaces, Zod schemas, DB types
   Use TYPE ANALYSIS FORMAT for EVERY type you report on.
   Include ALL fields, marking each as required or optional.
5. INTEGRATION POINTS — where new code would connect to existing code
   Show the exact function signatures at each integration point.
6. GAPS — what doesn't exist yet that this feature would need
7. RISKS — potential conflicts with existing code, performance concerns
8. TEST INFRASTRUCTURE — test runner, assertion library, mocking patterns,
   fixture/factory helpers (e.g., createTestUser), setup/teardown patterns.
   Show the actual test utility file paths and what they export.
9. ERROR PATTERNS — how errors are handled in this codebase
   (thrown exceptions vs Result types vs error codes, try/catch vs .catch())
   Show 2-3 examples with file paths.

Also read {PROJECT_STANDARDS} and summarize the key conventions.

## Output Format
Return a structured ARCHITECTURE_REPORT with all findings above.
Include exact file paths and line numbers throughout.

CRITICAL: For every file you reference, you MUST have actually read it.
If you found a file via Glob/Grep but did NOT read its contents, mark it:
  VERIFIED: NO — found via search, contents not read

At the end, include:
## Unverified References
{list of any file paths mentioned but not actually read}
```

Store the output as `ARCHITECTURE_REPORT`.

### Step 1B: Validate Architecture Report

Before proceeding, scan the `ARCHITECTURE_REPORT` for any `VERIFIED: NO` entries.
For each unverified file that appears in a potential ticket's file list:
- Spawn a quick Explore agent to read that specific file
- Update the report with verified data
- If the file doesn't exist, remove it from the report

---

## PHASE 2: PLAN GENERATION

Using the `ARCHITECTURE_REPORT`, generate the implementation plan.

### Sizing Rules (CRITICAL)

Each ticket must be completable by a single agent pair (Context + Worker)
in one worktree session. Enforce these constraints:

```
PER TICKET LIMITS:
├── Max files modified: 5
├── Max files created: 5
├── Max new lines of code: 400
├── Max test files: 2
├── Single responsibility: one logical unit of work
└── Must be independently testable
```

If a logical unit exceeds these limits, split it:
- Service with 8 functions → split into 2 tickets (4 functions each)
- Component with 600 lines → split into parent + child component tickets
- Migration + service + tests → split into migration ticket + service ticket

### Plan Structure

Generate the plan in this format:

```markdown
# Implementation Plan: {FEATURE}

## Overview
{2-3 sentence summary of what will be built}

## Architecture Decision
{Which approach was chosen and why, based on codebase analysis}

## Phases

### Implementation Wave 1: Foundation
{Database migrations, shared types, core services — things with no dependencies}

### Implementation Wave 2: Core Features
{Main implementation — services, components, hooks — depends on Wave 1}

### Implementation Wave 3: Integration
{Wiring, layout changes, route updates — depends on Wave 2}

### Implementation Wave 4: Polish
{Refactoring, extraction, optimization — depends on everything}

NOTE: These "Implementation Waves" describe the ticket execution order, NOT /sprint phases.
/sprint has its own Phase 0-8 for the orchestration lifecycle.

## Tickets

### {TICKET_NUMBER}. {TICKET_TITLE}
- **Wave:** {1|2|3|4} (Implementation Wave — NOT /sprint phase)
- **Priority:** {1=urgent|2=high|3=medium|4=low}
- **Depends on:** {list of ticket numbers, or "none"}
- **Tags:** {migration|schema|integration|service|component|hook|config — for rollback detection}
- **Files to create:**
  - `{exact/file/path.ts}` — {purpose, what it will export}
- **Files to modify:**
  - `{exact/file/path.ts}` — {which functions change, why}
- **Acceptance Criteria:**
  - [ ] {specific, testable requirement}
  - [ ] {specific, testable requirement}
  - [ ] All edge cases tested (populated after Phase 2.75)
  - [ ] Lint + typecheck pass
- **Estimated Complexity:** {S|M|L} (re-evaluated after Phase 2.75C)
- **Agent Notes:** {hints for the worker agent — patterns to follow, gotchas}
- **Edge Cases:** {populated after Phase 2.75A — placeholder "TBD" at plan time}
- **File Context:** {populated after Phase 2.5 — placeholder "TBD" at plan time}
- **Rollback:** {populated after Phase 2.75D if tagged migration/schema/integration}

### {TICKET_NUMBER}. {TICKET_TITLE}
...

## Dependency Graph
{ASCII diagram showing ticket dependencies}

## Sprint Config (for /sprint)
BRANCH_BASE: {BRANCH_BASE}
LINEAR_FILTER:
  team: "{LINEAR_TEAM}"
  label: "{LINEAR_SPRINT_LABEL}"
  status: ["Todo"]
PROJECT_STANDARDS: "{PROJECT_STANDARDS}"
BUILD_CMD: "{BUILD_CMD}"
LINT_CMD: "{LINT_CMD}"
TEST_CMD: "{TEST_CMD}"
TYPECHECK_CMD: "{TYPECHECK_CMD}"
E2E_CMD: "{E2E_CMD}"
COMMIT_PREFIX: "{COMMIT_PREFIX}"
MAX_LOOP_ITERATIONS: {MAX_LOOP_ITERATIONS}
HUMAN_IN_LOOP: {HUMAN_IN_LOOP}
PARTIAL_MERGE: {PARTIAL_MERGE}
SPRINT_DASHBOARD: {SPRINT_DASHBOARD}
```

---

## PHASE 2.5: FILE-LEVEL CONTEXT AGENTS (Deep Dives)

After Phase 2 produces the ticket list, we now know EXACTLY which files each ticket
will touch. Spawn parallel Context Agents to do deep reads of those specific files.

### Why This Phase Exists

The Phase 1 Explore agent does a broad sweep. But worker agents need DEEP context:
exact function signatures, type definitions, error patterns, caller chains, and
test conventions for the specific files they'll modify. Without this, workers
make assumptions — and assumptions cause incomplete implementations.

### Step 2.5A: Spawn Context Agents (Parallel)

For each ticket in the plan, spawn a **Context Agent** (Sonnet) that reads
the ticket's listed files in depth. Run up to `max_parallel` agents concurrently.

```yaml
subagent_type: "Explore"
model: "sonnet"
# Spawn one per ticket, or group tickets that share files
```

**Context Agent Prompt:**
```
{PASTE ANTI-HALLUCINATION RULES FROM GUARDRAILS SECTION ABOVE}

## LINEAR MCP RESTRICTION
You do NOT have permission to interact with Linear in ANY way.
Do NOT read tickets, post comments, or change statuses.
Your ONLY job is to analyze files. The orchestrator handles all Linear interactions.

You are analyzing files for a specific ticket. Read each file COMPLETELY
and extract detailed implementation context.

## Ticket Being Analyzed
Title: "{TICKET_TITLE}"
Purpose: "{TICKET_OVERVIEW}"

## Files to Analyze

### Files to MODIFY (read these in full):
{list from ticket plan — exact paths}

### Files to CREATE (read neighboring files for patterns):
{list from ticket plan — read similar existing files for conventions}

## For EACH File You Read, Extract:

### 1. Function Signatures & Behavior
For every exported function/method:
  - Full signature: name(params: Types): ReturnType
  - What it does (1 sentence)
  - Side effects (DB writes, API calls, event emissions)
  - Error handling (throws? returns null? Result type?)

### 2. Type Definitions
For every relevant interface/type/schema:
  Use TYPE ANALYSIS FORMAT:
  TYPE: {name}
  FILE: {path}:{line}
  FIELDS:
    - fieldName: type (required|optional) — purpose
  NULLABLE_FIELDS: {list of fields that can be null/undefined}
  ENUM_VALUES: {if applicable, list all valid values}

### 3. Caller Analysis (WHO calls these functions?)
  - Grep for imports of this module
  - Show which files import and use the functions being modified
  - Show HOW they call them (what args they pass)
  - This reveals "ghost dependencies" — code that will break if signatures change

### 4. Error Handling Patterns in This File
  - How does this file handle errors? (try/catch, .catch, Result, throw)
  - What error types are used? (custom Error classes? HTTP status codes?)
  - Show 1-2 examples from the actual file

### 5. Test Patterns (read the existing test file for this module)
  - Test runner: vitest / jest / other
  - Assertion style: expect().toBe() / assert / other
  - Mocking patterns: vi.mock() / jest.mock() / manual mocks
  - Fixtures: any factory functions (createTestUser, buildMockRequest, etc.)
  - Setup/teardown: beforeEach/afterEach patterns
  - Show the actual test file path and 1-2 representative test cases

### 6. Suggested Edge Cases (derived from type analysis)
For each function this ticket will create or modify, analyze its input types
and suggest SPECIFIC edge cases:
  - For string fields: empty string, very long string, special characters
  - For optional fields: undefined, null
  - For arrays: empty array, single item, very large array
  - For numbers: 0, negative, MAX_SAFE_INTEGER, NaN
  - For enums: invalid value outside the union
  - For async operations: concurrent calls, timeout, network failure
  - For DB operations: duplicate key, foreign key violation, connection loss

## Output Format
Return a TICKET_CONTEXT_REPORT with all sections above.
Every claim must include file path and line number.
Mark any unread files as UNVERIFIED.
```

Store each output as `TICKET_CONTEXT_REPORT[ticket_number]`.

### Step 2.5B: Flag Plan Mismatches

After Context Agents complete, check for mismatches:
- File listed in ticket but doesn't exist → FLAG for plan revision
- Function listed in ticket but has different signature than expected → UPDATE ticket
- File is more complex than estimated (>200 lines, >10 functions) → FLAG for potential split
- Missing import chain discovered (File A imports File B which wasn't in the ticket) → ADD to ticket

If any critical mismatches found:
```
MISMATCH DETECTED:
  Ticket: {ticket_number}
  Issue: {description}
  Action: {revise plan / split ticket / add file to ticket}
```

Loop back to Phase 2 to revise affected tickets before proceeding.

---

## PHASE 2.75: ENRICHMENT & VALIDATION

### Step 2.75A: Generate Explicit Edge Cases

For each ticket, using its `TICKET_CONTEXT_REPORT`, generate SPECIFIC, NAMED
edge cases as acceptance criteria. These replace the vague "handle edge cases" line.

**Edge Case Generation Rules:**
```
For each function the ticket creates or modifies:

1. Read the input type definition from TICKET_CONTEXT_REPORT
2. For EACH field in the input type:
   - If string → test: empty string, null/undefined if optional
   - If number → test: 0, negative, boundary values
   - If optional → test: omitted entirely
   - If array → test: empty array, single item
   - If enum/union → test: value outside the valid set
3. For the function's return type:
   - If Promise → test: rejection/error path
   - If nullable → test: when null is returned
4. For side effects:
   - If DB write → test: duplicate key, constraint violation
   - If API call → test: timeout, 4xx, 5xx responses
   - If event emission → test: no listeners registered
5. For concurrency:
   - If shared state → test: concurrent modifications
   - If idempotency expected → test: duplicate calls

OUTPUT FORMAT per ticket:
EDGE_CASES:
  - [ ] {function}: {input condition} → expected: {specific behavior}
  - [ ] {function}: {input condition} → expected: {specific behavior}
  ...
```

### Step 2.75B: Validate Dependencies (Import Graph Analysis)

Spawn a lightweight **Dependency Validator Agent** (Sonnet) to check that
ticket dependencies match actual code dependencies:

```yaml
subagent_type: "Explore"
model: "sonnet"
```

**Prompt:**
```
{PASTE ANTI-HALLUCINATION RULES FROM GUARDRAILS SECTION ABOVE}

## LINEAR MCP RESTRICTION
You do NOT have permission to interact with Linear in ANY way.
Your ONLY job is to validate dependencies. The orchestrator handles all Linear interactions.

You are validating that ticket dependencies are correct.

## Tickets and Their Files
{for each ticket: list ticket number, title, files to create, files to modify}

## Validation Steps

1. For each file listed in ANY ticket's "files to modify":
   - Read the file's imports
   - Check: does this file import from any file being CREATED by another ticket?
   - If yes → that ticket MUST be listed as a dependency

2. For each file being CREATED:
   - What will it export?
   - Which other ticket's files will import from it?
   - Those tickets MUST depend on this ticket

3. Check for CIRCULAR dependencies:
   - If Ticket A depends on Ticket B AND Ticket B depends on Ticket A → FLAG ERROR
   - Suggest how to break the cycle (extract shared types into a new ticket)

4. Check for MISSING dependencies:
   - If Ticket 5 modifies userService.ts which imports from notificationService.ts (Ticket 3)
     but Ticket 5 does NOT list Ticket 3 as a dependency → FLAG

## Output
DEPENDENCY_VALIDATION:
  CORRECT: {list of tickets with correct dependencies}
  MISSING: {list of missing dependency relationships}
  CIRCULAR: {list of circular dependency chains}
  SUGGESTED_FIXES: {how to fix each issue}
```

If MISSING or CIRCULAR dependencies found, update the plan before proceeding.

### Step 2.75C: Complexity Re-Evaluation

After enrichment, re-evaluate each ticket's complexity with real data:

```
For each ticket:
  1. Count actual functions to create/modify (from TICKET_CONTEXT_REPORT)
  2. Count actual edge cases generated (from Step 2.75A)
  3. Count files touched (including newly discovered imports from Step 2.75B)

  If ANY of these exceed sizing limits:
    - Functions > 6 → SPLIT into 2 tickets
    - Edge cases > 12 → SPLIT (too many paths for one agent)
    - Files > 5 → SPLIT by responsibility boundary
    - Estimated lines > 400 → SPLIT

  COMPLEXITY_REASSESSMENT:
    Ticket: {number}
    Original estimate: {S|M|L}
    Revised estimate: {S|M|L}
    Reason: {why changed, or "confirmed"}
    Action: {keep | split into N tickets}
```

If splits are needed, loop back to Phase 2 to regenerate affected tickets,
then re-run Phase 2.5 context agents for the new tickets.

### Step 2.75D: Generate Rollback Plans (for schema/integration tickets)

For tickets that modify database schemas, external integrations, or shared
configuration, generate a rollback specification:

```
For each ticket tagged as "migration", "schema", "integration", or "config":

ROLLBACK_PLAN:
  Ticket: {number} — {title}
  Changes: {what this ticket modifies}
  Rollback Steps:
    1. {specific undo action — e.g., "DROP COLUMN notifications.priority"}
    2. {specific undo action — e.g., "Remove webhook registration from config"}
  Rollback Risk: {LOW|MEDIUM|HIGH}
  Data Loss: {YES — describe what's lost | NO}
  Requires Downtime: {YES|NO}
```

This gets added to the ticket description so sprint agents and humans know
how to revert if something goes wrong.

---

## PHASE 3: APPROVAL GATE

Present the full plan to the user. Display:

1. **Summary** — what will be built, how many tickets, estimated total complexity
2. **Ticket tree** — compact view of all tickets with dependencies
3. **File impact** — total files created, modified, across all tickets
4. **Edge case coverage** — total edge cases across all tickets
5. **Dependency validation** — PASS/FAIL (any missing or circular deps?)
6. **Complexity changes** — any tickets that were split or resized in Phase 2.75C
7. **Rollback plans** — count of tickets with rollback specs
8. **Unverified items** — any remaining [UNVERIFIED] references (should be 0)
9. **Sprint config** — the exact `/sprint` config that will be generated

Then ask:

```
Ready to create {N} tickets across {M} phases on Linear?

Options:
1. "yes" / "create" — Create all tickets on Linear
2. "modify: {changes}" — Adjust specific tickets before creating
3. "dry-run" — Show exactly what would be created without touching Linear
4. "no" / "cancel" — Abort
```

### Handling Modifications

If the user says "modify":
- Parse their requested changes
- Update the affected tickets in the plan
- Re-display the modified tickets only
- Ask for approval again

### Dry Run Mode

If the user says "dry-run":
- Show the exact Linear API calls that would be made
- Show each ticket's title, description, labels, priority, dependencies
- Do NOT create anything on Linear
- Ask: "Looks good? Type 'create' to proceed."

---

## PHASE 4: CREATE ON LINEAR

After approval, create everything on Linear using MCP tools.

### Step 4A: Create Linear Project

```
Create a new Linear Project:
  - Name: "{FEATURE}" (truncated to 50 chars if needed)
  - Team: {LINEAR_TEAM}
  - Description: "{Overview from plan}"
```

Store the returned `PROJECT_ID`.

### Step 4B: Create Tickets (in dependency order)

Create tickets starting from Phase 1 (no dependencies) through Phase 4.
This ensures "depends on" relationships can reference already-created ticket IDs.

For each ticket:

```
Create a Linear Issue:
  - Team: {LINEAR_TEAM}
  - Title: "{TICKET_TITLE}"
  - Project: {PROJECT_ID}
  - Priority: {1-4}
  - Label: "{LINEAR_SPRINT_LABEL}"
  - Status: "Todo"
  - Description: (markdown, see template below)
```

**Ticket Description Template:**
```markdown
## Overview
{1-2 sentence summary of what this ticket implements}

## Files to Create
- `{exact/file/path.ts}` — {purpose, what it exports}

## Files to Modify
- `{exact/file/path.ts}` — {what changes, which functions affected}

## Acceptance Criteria
{checkboxes — copied from plan, SPECIFIC not vague}
- [ ] {specific, testable requirement}
- [ ] {specific, testable requirement}
- [ ] Lint + typecheck pass
- [ ] All edge cases below have test coverage

## Edge Cases (MANDATORY — Worker MUST implement tests for ALL)
{Generated from Phase 2.75A type analysis — NEVER vague}
- [ ] `{function}`: {input condition} → expected: {specific behavior}
- [ ] `{function}`: {input condition} → expected: {specific behavior}
- [ ] `{function}`: {input condition} → expected: {specific behavior}
{minimum 4 edge cases per ticket}

## Detailed File Context
{From Phase 2.5 TICKET_CONTEXT_REPORT — collapsed for humans, full for agents}

<details>
<summary>Click to expand file-level context</summary>

### {file_path.ts} (MODIFY)
- **Key functions:**
  - `{name}({params}: {Types}): {ReturnType}` — {what it does}
  - `{name}({params}: {Types}): {ReturnType}` — {what it does}
- **Error patterns:** {how this file handles errors — throw/Result/catch}
- **Callers:** {who imports and calls these functions, with file paths}

### {file_path.ts} (MODIFY)
- **Key functions:** ...
- **Error patterns:** ...
- **Callers:** ...

### Relevant Types
```typescript
// From {file_path.ts}:{line}
interface {TypeName} {
  field: type;      // required — {purpose}
  field?: type;     // optional — {purpose}, null means {meaning}
}
```

</details>

## Caller-Callee Contracts (Ghost Dependency Prevention)
{Functions your new code will CALL — exact signatures and behaviors}
- `{module}.{function}({params})` → returns {type}, throws on {condition}
- `{module}.{function}({params})` → returns {type}, side effects: {DB write, event emit, etc.}

## Test Patterns (Follow These Conventions)
- **Test runner:** {vitest|jest|other}
- **Test file location:** `{path/to/__tests__/or/path.test.ts}`
- **Mocking:** {vi.mock() with factory | jest.mock() | manual mocks}
- **Fixtures:** {createTestUser(), buildMockRequest(), etc. — with file paths}
- **Example test structure:**
```typescript
// From {existing_test_file.ts}:{line}
describe('{module}', () => {
  beforeEach(() => { /* {setup pattern} */ });
  it('should {behavior}', async () => {
    // {assertion pattern used in this project}
  });
});
```

## Implementation Notes
{Agent notes from plan — patterns to follow, existing code to reference}
{Include: which existing files to use as templates for new code}

## Dependencies
{Links to dependent tickets if any}
{Include: "This ticket's files import from: {list}" for dependency clarity}

## Rollback Plan
{Only for migration/schema/integration tickets — omit for pure code tickets}
- Rollback steps: {specific undo actions}
- Data loss risk: {YES/NO}
- Requires downtime: {YES/NO}

## Sizing
- Estimated complexity: {S|M|L} (re-evaluated after Phase 2.75C)
- Files to create: {count}
- Files to modify: {count}
- Edge cases to test: {count}
- This ticket is scoped for a single agent pair (Context + Worker) in one worktree.
```

### Step 4C: Set Dependencies

After all tickets are created, set "blocked by" relationships:

```
For each ticket with dependencies:
  Set relation: {TICKET_ID} is blocked by {DEPENDENCY_TICKET_ID}
```

This allows the `/sprint` Scheduler Agent to read dependency order
directly from Linear instead of guessing.

### Step 4D: Add Parent/Sub-Issue Nesting (where appropriate)

For tickets that form a logical group (e.g., a service + its tests,
or a component + its skeleton):

```
Set parent-child relationship:
  Parent: {PARENT_TICKET_ID} (the main feature ticket)
  Child: {SUB_TICKET_ID} (the supporting ticket)
```

Use nesting when:
- A service ticket has a separate test ticket
- A component has separate skeleton/loading state ticket
- A migration has a separate rollback ticket

Do NOT nest when tickets are truly independent.

---

## PHASE 5: SAVE PLAN & OUTPUT

### Step 5A: Save Plan as Reference

Save the full plan to `.claude/plans/`:

```bash
# Filename: kebab-case version of the feature name + date
# Example: real-time-notifications-20260226.md
```

### Step 5A.5: Tag Codebase Snapshot (Stale Risk Prevention)

```bash
# Tag the exact commit that the plan was generated against.
# If /sprint runs later on a different commit, its stale base detection
# can compare against this tag to know if file context has drifted.
git tag tickets-plan-$(date +%Y%m%d-%H%M%S) {BRANCH_BASE}
```

Display a staleness warning in the output:
```
⚠️  STALENESS WARNING: This plan was generated against commit {SHORT_HASH} of {BRANCH_BASE}.
If {BRANCH_BASE} has new commits before you run /sprint, the file context and function
signatures in ticket descriptions may be stale. /sprint's stale base detection (Phase 3
pre-check) will catch and rebase, but ticket descriptions won't auto-update.
If significant changes landed, consider re-running /tickets.
```

### Step 5B: Output Sprint Config

Display the ready-to-paste `/sprint` config:

```
## Tickets Created Successfully!

Created {N} tickets in Linear project "{FEATURE}":
{compact list: ticket ID → title → priority → status}

## Dependency Graph
{ASCII diagram}

## Ready to Sprint

Copy this to run /sprint:

/sprint

BRANCH_BASE: {BRANCH_BASE}
LINEAR_FILTER:
  team: "{LINEAR_TEAM}"
  label: "{LINEAR_SPRINT_LABEL}"
  status: ["Todo"]
  # NOTE: If resuming a partially-completed sprint, change to: status: ["Todo", "In Progress"]
PROJECT_STANDARDS: "{PROJECT_STANDARDS}"
BUILD_CMD: "{BUILD_CMD}"
LINT_CMD: "{LINT_CMD}"
TEST_CMD: "{TEST_CMD}"
TYPECHECK_CMD: "{TYPECHECK_CMD}"
E2E_CMD: "{E2E_CMD}"
COMMIT_PREFIX: "{COMMIT_PREFIX}"
MAX_LOOP_ITERATIONS: {MAX_LOOP_ITERATIONS}
HUMAN_IN_LOOP: {HUMAN_IN_LOOP}
PARTIAL_MERGE: {PARTIAL_MERGE}
SPRINT_DASHBOARD: {SPRINT_DASHBOARD}
```

### Step 5B.5: Recommend Coordination Mode

Based on the plan analysis, recommend a coordination mode for `/sprint`:

```
Analyze the ticket plan and recommend:

IF any of these are true → recommend Agent Teams:
  - More than 3 tickets have cross-ticket dependencies
  - Any ticket has complexity L (after Phase 2.75C re-evaluation)
  - More than 2 tickets modify the same files (high conflict risk)
  - Total edge cases across all tickets > 30

IF all of these are true → recommend Subagents (lower cost):
  - All tickets are independent (no dependencies)
  - All tickets are complexity S
  - Total tickets <= 3
  - Total edge cases < 15

Display recommendation in the Sprint Config output:
  ## Coordination Mode Recommendation
  Recommended: {Agent Teams | Subagents}
  Reason: {brief explanation based on plan characteristics}
  Note: /sprint will ask you to confirm this choice at Phase 0G.
```

### Step 5C: Save Sprint Hints (for /sprint Phase 0 acceleration)

Save ticket metadata that `/sprint` can use to pre-populate sprint-state.json:

```bash
cat > .claude/sprint-hints.json << 'HINTSEOF'
{
  "generated_at": "{ISO_TIMESTAMP}",
  "plan_commit": "{BRANCH_BASE_COMMIT_HASH}",
  "tickets": {
    "{TICKET_ID}": {
      "title": "{TICKET_TITLE}",
      "complexity": "{S|M|L}",
      "dependencies": ["{dep_ticket_ids}"],
      "files_to_create": ["{file_paths}"],
      "files_to_modify": ["{file_paths}"],
      "edge_case_count": {N}
    }
  },
  "coordination_mode_recommendation": "{agent-teams|subagents}",
  "total_tickets": {N},
  "total_edge_cases": {N}
}
HINTSEOF
```

If `/sprint` finds this file at Phase 0, it can:
- Pre-populate sprint-state.json ticket entries
- Use the recommended coordination mode as default
- Detect stale plans by comparing `plan_commit` to current `{BRANCH_BASE}`

### Step 5D: Offer Auto-Sprint

```
Want me to kick off /sprint now with this config? (yes/no)
```

If yes → execute `/sprint` with the generated config.
If no → done. User can run `/sprint` later.

---

## PERSISTENT MEMORY FOR EXPLORE AGENTS

The Phase 1 Explore agent benefits from project-level persistent memory. Over
multiple `/tickets` runs, it accumulates knowledge about the codebase:

```
Memory scope: project
Location: .claude/agent-memory/tickets-explore/

What gets saved:
  - Architecture patterns discovered (file structure, naming conventions)
  - Test infrastructure details (runner, mocking patterns, fixtures)
  - Error handling conventions
  - Common integration points
  - Type system patterns (Zod vs interface, Result vs throw)
  - Previous sprint learnings (what worked, what was underestimated)

How it's used:
  - Phase 1 Explore agent reads memory BEFORE starting analysis
  - This means repeated /tickets runs get faster and more accurate
  - Agent updates memory AFTER completing analysis with new findings
  - Stale entries (files that no longer exist) get pruned
```

To enable, the Explore agent prompt includes:
```
Before starting:
1. Check if progress.txt exists at repo root. If it does, read the Codebase Patterns
   section FIRST — these are learnings from previous sprints.
   If it doesn't exist, skip (Phase 0D creates it, but may not have run yet).
2. Check .claude/agent-memory/tickets-explore/ for previous analysis of this codebase.
   If directory doesn't exist or is empty, skip (first run).
   Use any relevant findings to accelerate your analysis, but VERIFY they are still
   current (files may have moved or changed since last analysis).

After completing: Update your agent memory with:
- New architecture patterns discovered
- Test infrastructure details
- Error handling conventions
- Integration points mapped
- Any corrections to previous memory entries
Save to: .claude/agent-memory/tickets-explore/ (directory created by Phase 0D)
```

---

## ROLLBACK

### Automatic Rollback (partial creation failure)

If ticket creation fails mid-way through Phase 4 (e.g., Linear API error after
creating 5 of 8 tickets), the orchestrator MUST:

```
1. Track created ticket IDs as they are created:
   created_ticket_ids = []
   for each ticket in plan:
       result = create Linear issue(...)
       if result SUCCESS:
           created_ticket_ids.append(result.id)
       if result FAILED:
           LOG ERROR: "Failed to create ticket {ticket.title}: {error}"
           # Offer rollback
           if created_ticket_ids.length > 0:
               ask user: "Created {created_ticket_ids.length} of {total} tickets before failure.
                         Options:
                         1. Keep created tickets and retry remaining
                         2. Delete all created tickets and abort
                         3. Keep created tickets and abort (partial plan)"
               if user selects "delete all":
                   for each id in created_ticket_ids:
                       delete Linear issue(id)
                   LOG: "Rolled back {created_ticket_ids.length} tickets"
           break
```

### Manual Rollback (user-initiated)

If something goes wrong after tickets are created on Linear:

```
/tickets created {N} tickets in project "{FEATURE}".

To undo:
1. Open Linear → Projects → "{FEATURE}"
2. Select all tickets → Bulk action → Delete
3. Delete the project

Or tell me: "delete the tickets you just created"
→ I'll use Linear MCP to remove all tickets with label "{LINEAR_SPRINT_LABEL}"
   that were created in the last 10 minutes.
```

---

## ORCHESTRATOR RULES

1. **Stay lightweight.** Delegate codebase research to Explore/Context agents.
2. **Enforce sizing.** Never create a ticket that exceeds per-ticket limits.
   Re-evaluate after Phase 2.75C with real data — initial estimates are provisional.
3. **File paths are mandatory and VERIFIED.** Every ticket must list exact files.
   No [UNVERIFIED] paths allowed in final tickets.
4. **Acceptance criteria are mandatory and SPECIFIC.** No vague criteria like
   "handle edge cases." Every criterion must be independently testable.
5. **Edge cases are mandatory.** Every ticket must have ≥4 explicit edge cases
   derived from actual type analysis (Phase 2.75A). Never skip this.
6. **Dependencies are mandatory and VALIDATED.** Every ticket must declare
   dependencies, confirmed by import graph analysis (Phase 2.75B).
7. **File context is mandatory.** Every ticket must include Detailed File Context
   from Phase 2.5. Workers should never guess at function signatures.
8. **Caller-callee contracts are mandatory.** If new code calls existing functions,
   the exact signatures and behaviors must be documented in the ticket.
9. **Test patterns are mandatory.** Every ticket must include the project's test
   conventions so workers don't reinvent mocking/fixture patterns.
10. **Anti-hallucination rules AND LINEAR MCP RESTRICTION are injected into EVERY agent.** No exceptions.
    Every Explore, Context, and Validation agent gets both guardrails and the restriction.
    Only the orchestrator itself touches Linear (Phase 4 ticket creation).
11. **Always save the plan.** Even if user cancels Linear creation, save the .md.
12. **Sprint config is always generated.** Even in dry-run mode. Must include ALL fields
    that `/sprint` expects: COMMIT_PREFIX, HUMAN_IN_LOOP, PARTIAL_MERGE, SPRINT_DASHBOARD.
13. **Rollback plans for schema/integration tickets.** Any ticket tagged
    migration, schema, or integration MUST have a rollback specification.
14. **Two-pass research is not optional.** Phase 1 (broad) + Phase 2.5 (deep)
    must both run. Do NOT skip Phase 2.5 to save time.
15. **Baseline build must pass.** Phase 0C verifies the base branch builds. Tickets
    generated against a broken codebase have unreliable file context.
16. **Tag the codebase snapshot.** Phase 5A.5 tags the exact commit the plan was
    generated against. /sprint uses this to detect stale plans.
17. **Save sprint hints.** Phase 5C writes .claude/sprint-hints.json for /sprint
    to pre-populate state and detect plan staleness.
18. **Track partial creation for rollback.** Phase 4 must track created ticket IDs
    as they are created, so a mid-creation failure can be rolled back.
19. **Recommend coordination mode.** Phase 5B.5 analyzes ticket complexity and
    dependencies to recommend Agent Teams vs Subagents for /sprint.

---

## FLOW DIAGRAM

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
│  │   └── Loop to Phase 2 if splits      │
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

---

## AGENT INVENTORY

| Agent | Phase | Model | Purpose | Gets Guardrails? |
|-------|-------|-------|---------|-----------------|
| Broad Explore | 1 | Sonnet | Architecture sweep, patterns, types, test infra | YES |
| Validation Read | 1B | Sonnet | Verify [UNVERIFIED] file references | YES |
| Context Agent (×N) | 2.5 | Sonnet | Deep file reads per ticket — signatures, callers, tests | YES |
| Dependency Validator | 2.75B | Sonnet | Import graph analysis, circular dep detection | YES |

**All agents receive ANTI-HALLUCINATION RULES in their prompt. No exceptions.**

---

## EXECUTION CHECKLIST

Before presenting to user at Phase 3, verify:

```
[ ] Phase 0: Linear MCP connected, git clean, baseline build passes
[ ] Phase 0: progress.txt initialized (or already exists)
[ ] Phase 0: .claude/agent-memory/tickets-explore/ directory created
[ ] Phase 0: .gitignore includes worktrees, sprint-dashboard, sprint-state, sprint-hints
[ ] Phase 1: ARCHITECTURE_REPORT has 0 UNVERIFIED references
[ ] Phase 1: Test infrastructure documented (runner, mocking, fixtures)
[ ] Phase 1: Error patterns documented with examples
[ ] Phase 2: All tickets within sizing limits
[ ] Phase 2: All tickets have tags (migration/schema/service/component/etc)
[ ] Phase 2.5: TICKET_CONTEXT_REPORT exists for every ticket
[ ] Phase 2.5: No plan mismatches flagged (or all resolved)
[ ] Phase 2.75A: Every ticket has ≥4 explicit edge cases
[ ] Phase 2.75B: Dependency validation PASSED (no missing/circular)
[ ] Phase 2.75C: Complexity re-evaluated — no oversized tickets remain
[ ] Phase 2.75D: Rollback plans exist for all schema/migration/integration tickets
[ ] All file paths are VERIFIED (no [UNVERIFIED] in any ticket)
[ ] All edge cases reference specific functions and expected behaviors
[ ] All tickets include Detailed File Context section
[ ] All tickets include Caller-Callee Contracts section
[ ] All tickets include Test Patterns section
[ ] Sprint config generated (includes COMMIT_PREFIX, HUMAN_IN_LOOP, PARTIAL_MERGE, SPRINT_DASHBOARD)
[ ] Codebase snapshot tagged (tickets-plan-{timestamp})
[ ] Staleness warning displayed
[ ] Sprint hints saved (.claude/sprint-hints.json)
[ ] Coordination mode recommendation provided
[ ] Partial creation rollback tracking in place for Phase 4
```

---

## EXAMPLE USAGE

```
User: /tickets Add real-time notifications when compliance issues are detected

Phase 0: Pre-flight ✓ (Linear connected, git clean, build passes, support files initialized)

Phase 1: Codebase analysis (Broad Explore agent)
  ├── Architecture: Next.js + Supabase + Zustand
  ├── Related code: 4 services, 2 hooks mapped (all VERIFIED)
  ├── Types: ComplianceIssue, UserPreferences (full definitions captured)
  ├── Test infra: vitest + vi.mock() + test factories in __tests__/helpers/
  ├── Error patterns: thrown errors with custom AppError class
  └── 0 unverified references ✓

Phase 2: Generated plan:
  8 tickets across 3 waves (edge cases + context = TBD)
  ├── Wave 1: Migration + notification service (2 tickets, tagged: migration, service)
  ├── Wave 2: Event hooks + queue + templates (4 tickets, tagged: service, hook)
  └── Wave 3: UI components + settings page (2 tickets, tagged: component)

Phase 2.5: File-level context agents (4 parallel)
  ├── Context for CLA-40: migration — DB schema analyzed, rollback identified
  ├── Context for CLA-41: service — 6 functions mapped, 3 callers found
  ├── Context for CLA-42,43,44: shared service files — cross-ticket imports detected
  ├── Context for CLA-45,46,47: UI — component patterns + hook conventions extracted
  ├── 1 mismatch: CLA-42 needs import from CLA-43 (dependency was missing) → FIXED
  └── All files VERIFIED ✓

Phase 2.75: Enrichment & validation
  ├── Edge cases: 47 total across 8 tickets (min 4 per ticket) ✓
  ├── Dependencies: VALIDATED — 1 missing dep found and added ✓
  ├── Complexity: CLA-41 re-evaluated M→L, split into CLA-41a + CLA-41b
  ├── Rollback: CLA-40 has rollback plan (DROP COLUMN, no data loss) ✓
  └── Now 9 tickets across 3 waves

Phase 3: Approval?
  Summary: 9 tickets, 47 edge cases, all deps validated, 1 rollback plan
User: "yes"

Phase 4: Created on Linear:
  CLA-40: Create notifications table migration (P2, Wave 1, rollback: ✓)
  CLA-41a: Implement notificationService core (P2, Wave 1, 6 edge cases)
  CLA-41b: Implement notificationService delivery (P2, Wave 1, 5 edge cases)
  CLA-42: Add issue detection event hook (P2, Wave 2, blocked by CLA-41a)
  CLA-43: Create notification queue with retry (P3, Wave 2, blocked by CLA-41a)
  CLA-44: Build notification templates (P3, Wave 2, blocked by CLA-41b)
  CLA-45: Add Supabase real-time subscription (P2, Wave 2, blocked by CLA-40)
  CLA-46: Create NotificationBell component (P2, Wave 3, blocked by CLA-45)
  CLA-47: Add notification preferences page (P3, Wave 3, blocked by CLA-41a)

Phase 5: Plan saved to .claude/plans/real-time-notifications-20260302.md
  Codebase snapshot tagged. Sprint hints saved. Explore agent memory updated.
  Coordination mode recommendation: Agent Teams (3+ cross-dependencies, 47 edge cases)

Sprint config ready. Run /sprint to execute.
```
