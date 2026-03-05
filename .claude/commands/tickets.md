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
MAX_PARALLEL_CONTEXT_AGENTS: 4          # Max concurrent Context Agents in Phase 2.5 (1-8, limited by API rate limits)
MAX_LOOP_ITERATIONS: 3
HUMAN_IN_LOOP: false                    # true = pause for human review before marking Done
PARTIAL_MERGE: true                     # true = merge completed tickets even if some are stuck
SPRINT_DASHBOARD: true                  # true = write sprint-dashboard.md after each phase
```

If the user doesn't provide config, use the defaults above and ask only for FEATURE.

---

## PHASE 0: PRE-FLIGHT

### Step 0-Pre: Load Problem Statement (from /define)

Check if `/define` was run before this command. Validate schema, required sections, and freshness.

```bash
if [ -f .claude/problem-statement.md ]; then
  echo "📋 Found problem statement from /define. Loading..."
  PROBLEM_STATEMENT = read .claude/problem-statement.md

  # ─── SCHEMA VALIDATION ───
  # Required header fields (added in schema_version 2):
  schema_version = extract "schema_version:" from header line
  generated_at = extract "generated_at:" from header line
  generated_commit = extract "generated_commit:" from header line

  if schema_version is missing or < 2:
      echo "⚠️  Problem statement has old or missing schema_version (found: ${schema_version:-'none'})."
      echo "    Expected schema_version: 2. Re-run /define to regenerate."
      echo "    Proceeding with best-effort extraction — some fields may be missing."
      PROBLEM_STATEMENT_SCHEMA_VALID = false
  else:
      PROBLEM_STATEMENT_SCHEMA_VALID = true
  fi

  # ─── REQUIRED SECTIONS VALIDATION ───
  # These sections MUST exist for /tickets to function correctly.
  # Use heading detection: grep for "^## {heading}" (case-insensitive).
  REQUIRED_SECTIONS = ["Problem", "Definition of Done", "Testing Strategy", "Constraints"]
  missing_sections = []

  for section in REQUIRED_SECTIONS:
      if ! grep -qi "^## ${section}" .claude/problem-statement.md; then
          missing_sections.append(section)
      fi
  done

  if missing_sections is not empty:
      echo "⚠️  Problem statement is missing required sections: ${missing_sections}"
      echo "    These sections are needed for ticket generation. Re-run /define to fix."
      echo "    Proceeding with available sections — quality may be reduced."
  fi

  # ─── SUB-SECTION VALIDATION ───
  # Key sub-sections that downstream consumers depend on:
  EXPECTED_SUBSECTIONS = ["User Journey", "Success Criteria", "Implied Features", "Codebase Snapshot"]
  missing_subsections = []

  for subsection in EXPECTED_SUBSECTIONS:
      if ! grep -qi "^### ${subsection}" .claude/problem-statement.md; then
          missing_subsections.append(subsection)
      fi
  done

  if missing_subsections is not empty:
      echo "    Note: Missing sub-sections: ${missing_subsections} (non-blocking but reduces quality)"
  fi

  # ─── STALENESS CHECK ───
  # Compare the commit SHA when /define ran against current HEAD.
  # If the codebase changed significantly, the problem statement's Codebase Snapshot
  # may be outdated (new modules, changed test infra, etc.).
  if generated_commit is not empty:
      current_head=$(git rev-parse HEAD)
      if [ "$generated_commit" != "$current_head" ]; then
          # Count how many commits apart we are
          commits_apart=$(git rev-list --count ${generated_commit}..HEAD 2>/dev/null || echo "unknown")
          echo "⚠️  STALE PROBLEM STATEMENT: /define ran at ${generated_commit:0:7}, HEAD is now ${current_head:0:7}"
          echo "    ${commits_apart} commits apart. The Codebase Snapshot may be outdated."
          echo "    Consider re-running /define if the codebase changed significantly."
          PROBLEM_STATEMENT_STALE = true
      else
          PROBLEM_STATEMENT_STALE = false
      fi
  else
      echo "    Note: No generated_commit in problem statement (pre-v2 format). Cannot check staleness."
      PROBLEM_STATEMENT_STALE = "unknown"
  fi

  # ─── EXTRACT KEY FIELDS ───
  # These are used throughout /tickets:
  # - PROBLEM_DESCRIPTION: Enriches FEATURE context beyond the one-liner
  # - SUCCESS_CRITERIA: Used in Phase 3 (Approval Gate) to validate all criteria have tickets
  # - USER_JOURNEY: Used in Phase 2.75 to generate more targeted edge cases
  # - TESTING_STRATEGY: Used to set test expectations per ticket
  # - IMPLIED_FEATURES: Cross-checked against generated ticket list
  # - CONSTRAINTS: Passed to Context Agents as hard constraints
  # - CODEBASE_SNAPSHOT: Accelerates Phase 1 (Explore Agent already knows the stack)
  #
  # PARSING STRATEGY: Extract each section by finding its ## heading and reading
  # until the next ## heading (or end of file). See Step 0-Pre Parsing Helper below.

  echo "  Problem: $(head -n1 of Problem section)"
  echo "  Success criteria: {N} items"
  echo "  Testing level: {level}"
  echo "  Constraints: {count or 'none'}"
  echo "  Schema valid: ${PROBLEM_STATEMENT_SCHEMA_VALID}"
  echo "  Stale: ${PROBLEM_STATEMENT_STALE}"
  echo ""
  echo "Tip: /define context will enrich ticket quality. The Explore Agent will"
  echo "     skip basic stack detection since /define already captured it."
else
  echo "ℹ️  No problem statement found. Running without /define context."
  echo "   Tip: Run /define first for better ticket quality."
  PROBLEM_STATEMENT = null
fi
```

#### Step 0-Pre Parsing Helper

To extract sections from the markdown problem statement, use this heading-based parser:

```bash
# Extract a section from problem-statement.md by its heading.
# Returns everything from "## {heading}" to the next "## " heading (or EOF).
# Usage: extract_section "Problem" → returns the Problem section content
#        extract_section "User Journey" → returns the User Journey subsection

extract_section() {
    local heading="$1"
    local file="${2:-.claude/problem-statement.md}"  # Accepts optional file path argument

    # ROBUSTNESS: This parser handles:
    #   1. Code fences — headings inside ``` blocks are ignored (not treated as section boundaries)
    #   2. Missing sections — returns empty string + exit code 1 if heading not found
    #   3. Body text matching — only matches headings at line start (^## ), not heading text in paragraphs
    #   4. Heading level awareness — stops at same or higher level heading (## stops at ## or #, not ###)

    local result
    result=$(awk -v heading="$heading" '
        BEGIN { IGNORECASE=1; found=0; level=0; in_fence=0 }

        # Track code fences — toggle on/off when we see ``` at line start
        /^```/ { in_fence = !in_fence; if (found) print; next }

        # Inside a code fence, pass through without checking for headings
        in_fence { if (found) print; next }

        # Only match headings at LINE START: must begin with ## (not in body text)
        /^#{1,6} / {
            # Count the heading level (number of # characters)
            match($0, /^#+/)
            current_level = RLENGTH

            if (found) {
                # Stop if we hit a heading at the SAME or HIGHER level (≤ our level number)
                if (current_level <= level) { exit }
                # Sub-headings (deeper level) are part of this section — include them
                print
                next
            }

            # Check if this heading matches our target (case-insensitive substring match on heading TEXT only)
            # Strip the leading #s and whitespace to get just the heading text
            heading_text = $0
            sub(/^#+[[:space:]]*/, "", heading_text)
            if (index(tolower(heading_text), tolower(heading)) > 0) {
                found = 1
                level = current_level
                next
            }
        }

        found { print }

        END { if (!found) exit 1 }
    ' "$file")

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""  # Return empty string for missing sections
        return 1  # Caller can check: if ! section=$(extract_section "Foo"); then echo "missing"; fi
    fi
    echo "$result"
}

# Example usage throughout /tickets:
# PROBLEM_DESCRIPTION=$(extract_section "Problem")
# USER_JOURNEY=$(extract_section "User Journey")
# SUCCESS_CRITERIA=$(extract_section "Success Criteria")
# IMPLIED_FEATURES=$(extract_section "Implied Features")
# TESTING_STRATEGY=$(extract_section "Testing Strategy")
# CONSTRAINTS=$(extract_section "Constraints")
# CODEBASE_SNAPSHOT=$(extract_section "Codebase Snapshot")
#
# Handling missing sections (returns empty string + exit code 1):
# if ! CONSTRAINTS=$(extract_section "Constraints"); then
#     echo "No Constraints section found — proceeding without constraints"
#     CONSTRAINTS=""
# fi
#
# Custom file path (default is .claude/problem-statement.md):
# SECTION=$(extract_section "Overview" ".claude/plans/my-plan.md")
```

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
git check-ignore -q .claude/problem-statement.md 2>/dev/null || echo ".claude/problem-statement.md" >> .gitignore
git check-ignore -q .claude/sprint-hints.json 2>/dev/null || echo ".claude/sprint-hints.json" >> .gitignore
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

## Accumulated Learnings (from progress.txt)
If progress.txt exists at the repo root, read it FIRST and absorb the "Codebase Patterns"
section. These are patterns discovered by prior sprint agents that may inform your analysis.
If progress.txt does NOT exist (first sprint on this repo), skip this step — do not error.

## Persistent Memory (from previous /tickets runs)
Check .claude/agent-memory/tickets-explore/ for previous analysis of this codebase.
If the directory doesn't exist or is empty, skip (first run on this repo).
If previous analysis exists:
  - Read it and use relevant findings to ACCELERATE your analysis
  - But VERIFY findings are still current — files may have moved or changed
  - Stale entries (referencing files that no longer exist) should be noted for pruning

After completing your analysis, UPDATE your agent memory:
  - Save to .claude/agent-memory/tickets-explore/
  - Include: architecture patterns, test infrastructure, error handling conventions,
    integration points, and any corrections to previous entries

Analyze the codebase for implementing: "{FEATURE}"

## Problem Statement Context (from /define)
{IF PROBLEM_STATEMENT is not null:
  The orchestrator extracts each section using the extract_section() parser from Step 0-Pre.
  PASTE these extracted sections into this prompt:

  ### Problem
  {extract_section("Problem")}

  ### User Journey
  {extract_section("User Journey")}
  → Focus your codebase analysis on the files/modules these journey steps will touch.

  ### Constraints
  {extract_section("Constraints")}
  → Treat these as hard limits when mapping implementation paths.

  ### Codebase Snapshot
  {extract_section("Codebase Snapshot")}
  → Skip re-discovering stack, test infra, and directory structure — this is already known.
    Focus your analysis time on code-level patterns, function signatures, and test conventions.

  {IF PROBLEM_STATEMENT_STALE == true:
    ⚠️  NOTE: This problem statement is {commits_apart} commits behind HEAD.
    The Codebase Snapshot may be outdated. Verify any stack/infra claims during your analysis.
  }
}
{IF PROBLEM_STATEMENT is null:
  No problem statement available. Analyze broadly based on FEATURE description.
}

## What to Map
1. ARCHITECTURE — project structure, key directories, framework/stack used
   {IF Codebase Snapshot section was provided above:
     SKIP basic stack detection (language, framework, key deps, directory structure).
     The Codebase Snapshot already provides: stack, test infra, key dirs, auth/db/API presence.
     Instead, go DEEPER: analyze code-level architecture patterns, module boundaries,
     service layers, and how the existing modules communicate.
   }
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

**NOTE:** Phase 2 (ticket generation) has NOT run yet at this point. Step 1B validates
the ARCHITECTURE_REPORT itself — not ticket file lists (those are validated in Phase 2.5).

For each unverified file that appears in the report's INTEGRATION POINTS or EXISTING CODE sections:
- Spawn a quick Explore agent to read that specific file
- Update the report with verified data (function signatures, line counts, exports)
- If the file doesn't exist, remove it from the report and note the correction

Also check the RISKS section: if risks were identified but lack file path evidence,
spawn a quick read to confirm or dismiss each risk with actual file contents.

---

## PHASE 2: PLAN GENERATION

Using the `ARCHITECTURE_REPORT`, generate the implementation plan.

### Pre-Generation: Consume ARCHITECTURE_REPORT Risks

Before generating tickets, review the RISKS section of ARCHITECTURE_REPORT:
```
For each risk in ARCHITECTURE_REPORT.RISKS:
  - If risk type is "conflict with existing code":
    → Add to affected ticket's Agent Notes: "⚠️ RISK: {risk description}. Check {file}:{lines} before modifying."
  - If risk type is "performance concern":
    → Add acceptance criterion: "Performance: {specific metric} must not regress"
  - If risk type is "missing pattern/convention":
    → Add to Agent Notes: "No existing pattern for this. Create new convention and document in progress.txt."
  - If risk has no clear ticket assignment:
    → Create a dedicated risk-mitigation ticket (complexity S, Wave 1)
```

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
  status: ["Todo"]                       # Valid values: "Todo", "In Progress", "In Review", "Done", "Canceled"
                                          # For fresh sprint: ["Todo"]
                                          # For resuming: ["Todo", "In Progress"]
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
MAX_PARALLEL_CONTEXT_AGENTS: {MAX_PARALLEL_CONTEXT_AGENTS}
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
the ticket's listed files in depth. Run up to `MAX_PARALLEL_CONTEXT_AGENTS` (default: 4) agents concurrently.
Group tickets that share >50% of their files into a single Context Agent to avoid redundant reads.

```yaml
subagent_type: "Explore"
model: "sonnet"
# Grouping strategy: Compare file lists across tickets.
# If ticket A and ticket B share >50% of their "files to modify",
# merge them into a single Context Agent run (saves API calls + avoids redundant reads).
# The agent prompt includes BOTH tickets' context needs.
# Otherwise, spawn one Context Agent per ticket.
# Max concurrent: MAX_PARALLEL_CONTEXT_AGENTS (default: 4)
```

**Context Agent Prompt:**
```
{PASTE ANTI-HALLUCINATION RULES FROM GUARDRAILS SECTION ABOVE}

## LINEAR MCP RESTRICTION
You do NOT have permission to interact with Linear in ANY way.
Do NOT read tickets, post comments, or change statuses.
Your ONLY job is to analyze files. The orchestrator handles all Linear interactions.

## Accumulated Learnings (from progress.txt)
If progress.txt exists at the repo root, read it FIRST. The "Codebase Patterns" section
contains patterns from prior sprints that may affect your analysis (e.g., import aliases,
mock patterns, error handling conventions). If progress.txt does NOT exist, skip — do not error.

You are analyzing files for a specific ticket. Read each file COMPLETELY
and extract detailed implementation context.

## Problem Statement Context (from /define)
{IF PROBLEM_STATEMENT is not null:
  ### Constraints
  {extract_section("Constraints")}
  → These are HARD LIMITS. Flag any file patterns that would violate these constraints.

  ### Testing Strategy
  Testing Level: {extract_section("Testing Strategy") — first line or "Standard" default}
  → This determines how many edge cases and test patterns you should extract.
    Full = exhaustive edge cases. Standard = happy + error paths. Minimal = core logic only.

  ### User Journey (relevant steps for this ticket)
  {Extract ONLY the user journey steps relevant to this ticket's purpose — not the full journey.
   If the ticket implements step 3 of the journey, include step 3 and its immediate neighbors.}
  → Use this to understand the UX context for the code you're analyzing.
}
{IF PROBLEM_STATEMENT is null:
  No problem statement available. Analyze based on ticket description only.
}

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

**TICKET_CONTEXT_REPORT Structure:**
```yaml
TICKET_CONTEXT_REPORT:
  ticket_number: {N}
  ticket_title: "{title}"
  files_analyzed:
    - path: "{exact/file/path.ts}"
      status: "MODIFY" | "CREATE_NEIGHBOR"  # CREATE_NEIGHBOR = read similar file for patterns
      verified: true | false
      line_count: {N}
      functions:
        - name: "{functionName}"
          signature: "{full TypeScript signature}"
          behavior: "{1-sentence description}"
          side_effects: ["{DB write}", "{event emission}", ...]
          error_handling: "throws AppError" | "returns null" | "Result<T,E>"
      types:
        - name: "{TypeName}"
          file_line: "{path}:{line}"
          fields: ["{fieldName}: {type} (required|optional) — {purpose}"]
          nullable_fields: ["{fieldName}"]
      callers:
        - file: "{caller/file/path.ts}"
          function: "{callerFunction}"
          usage: "{how it calls this module — args passed, return value used}"
  error_patterns:
    style: "throw" | "Result" | "error code" | "mixed"
    examples: ["{1-2 code snippets from actual files}"]
  test_patterns:
    runner: "vitest" | "jest" | "other"
    test_file: "{path/to/test.ts}"
    mock_style: "vi.mock()" | "jest.mock()" | "manual"
    fixtures: ["{factoryFunction} from {file}"]
    example_structure: "{representative test case snippet}"
  suggested_edge_cases:
    - function: "{functionName}"
      input: "{condition — e.g., empty string for userId}"
      expected: "{specific behavior — e.g., throws ValidationError}"
  unverified_files: ["{paths found but not read}"]
```

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
   - What will it export? (Infer from the ticket's acceptance criteria, agent notes,
     and the "Files to create" description — e.g., "notification.service.ts — exports
     handleNotification, getUnreadCount" tells you the planned exports.)
   - If the ticket description doesn't specify exports, FLAG it:
     "⚠️ Ticket {N} creates {file} but doesn't declare its exports.
      Cannot verify downstream dependencies. Add export list to ticket description."
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
9. **Problem statement coverage** (if PROBLEM_STATEMENT loaded) — validate using keyword matching:

   **Algorithm: Keyword Extraction + Ticket Scanning**

   **Helper: `extract_nouns_and_key_phrases(text)`**
   ```
   extract_nouns_and_key_phrases(text):
       # PURPOSE: Extract 2-4 meaningful keywords/phrases from a success criterion
       # for matching against ticket titles and descriptions.
       #
       # ALGORITHM:
       # 1. Lowercase the text
       # 2. Remove common stop words: a, an, the, is, are, was, were, be, been,
       #    has, have, had, do, does, did, will, shall, should, can, could, may,
       #    must, with, from, for, and, or, but, in, on, at, to, of, by, as, it,
       #    its, that, this, when, if, then, than, also, each, every, all, any
       # 3. Remove common verbs: renders, displays, shows, handles, creates,
       #    returns, sends, receives, validates, checks, updates, saves, loads
       # 4. Extract remaining multi-word phrases (2-3 word sequences) as primary keywords
       #    Example: "notification bell" > "notification" alone
       # 5. Extract remaining single words (4+ characters) as fallback keywords
       # 6. Return unique list of 2-4 keywords, preferring multi-word phrases
       #
       # EXAMPLES:
       #   "Notification bell renders in top nav with unread count"
       #   → ["notification bell", "top nav", "unread count"]
       #
       #   "User can mark individual notifications as read"
       #   → ["mark notifications", "individual notifications", "read"]
       #
       #   "API returns paginated notification history"
       #   → ["paginated notification", "notification history"]
       #
       # FALLBACK: If fewer than 2 keywords extracted, split text on spaces
       # and return the 2-3 longest words (excluding stop words).

       keywords = []
       cleaned = lowercase(text)
       cleaned = remove_stop_words(cleaned)
       cleaned = remove_common_verbs(cleaned)

       # Extract bigrams (2-word phrases) first — more specific matches
       words = split(cleaned)
       for i in range(len(words) - 1):
           bigram = words[i] + " " + words[i+1]
           if len(words[i]) >= 3 and len(words[i+1]) >= 3:
               keywords.append(bigram)

       # Add remaining significant single words not already in a bigram
       for word in words:
           if len(word) >= 4 and not any(word in k for k in keywords):
               keywords.append(word)

       # Deduplicate and limit to 2-4 keywords
       keywords = unique(keywords)[:4]

       # Fallback: if fewer than 2, use longest words from original text
       if len(keywords) < 2:
           keywords = sorted(words, key=len, reverse=True)[:3]

       return keywords
   ```

   ```
   For each success_criterion in SUCCESS_CRITERIA:
       # Step 1: Extract 2-4 unique keywords from the criterion
       #   "Notification bell renders in top nav with unread count"
       #   → keywords: ["notification bell", "top nav", "unread count"]
       keywords = extract_nouns_and_key_phrases(criterion)

       # Step 2: Search all ticket titles + descriptions for keyword matches
       matched_tickets = []
       for ticket in ALL_TICKETS:
           ticket_text = ticket.title + " " + ticket.description
           match_count = count keywords present in ticket_text (case-insensitive)
           if match_count >= 1:
               matched_tickets.append(ticket.id)

       # Step 3: Report
       if matched_tickets is empty:
           FLAG: "⚠️ UNCOVERED: '{criterion}' — no ticket matches keywords {keywords}"
       else:
           LOG: "✓ '{criterion}' covered by: {matched_tickets}"
   ```

   **For implied features:**
   ```
   For each implied_feature in IMPLIED_FEATURES:
       # Implied features are more specific (e.g., "Mark-as-read mutation")
       # Search ticket titles for direct substring match (case-insensitive)
       matched = find tickets where title contains any word from implied_feature (3+ chars)
       if not matched:
           FLAG: "⚠️ UNCOVERED: Implied feature '{implied_feature}' has no corresponding ticket"
   ```

   **For testing strategy:**
   - If testing level is "Full" → every ticket MUST have an E2E scenario or a note explaining why not
   - If testing level is "Standard" → every ticket MUST have unit test expectations
   - If testing level is "Minimal" → at least core logic tickets must have test expectations

   **For constraints:**
   - For each constraint, grep all ticket descriptions for violation keywords
   - E.g., constraint "Must NOT touch auth module" → check no ticket's files_to_modify includes auth/

   **If ANY success criterion is UNCOVERED:** present the gaps to the user in the approval prompt.
   The user can choose to add tickets, modify existing tickets, or accept the gaps.
10. **Sprint config** — the exact `/sprint` config that will be generated

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
- **Re-enrichment check:** For each modified ticket, determine if re-enrichment is needed:
  ```
  NEEDS_RE_ENRICHMENT if ANY of:
    - Files to create/modify changed → re-run Phase 2.5 Context Agent for this ticket
    - Dependencies changed → re-run Phase 2.75B Dependency Validator
    - Ticket was split or merged → re-run Phase 2.5 + 2.75A (edge cases) + 2.75C (sizing)
    - Acceptance criteria changed substantially → re-run Phase 2.75A (edge cases)

  SKIP_RE_ENRICHMENT if ONLY:
    - Title or description wording changed (cosmetic)
    - Priority changed
    - Wave/phase assignment changed without file changes
    - Agent notes updated
  ```
- If re-enrichment needed: run the minimal set of phases, then re-display
- If no re-enrichment needed: re-display the modified tickets only
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

Create tickets starting from Wave 1 (no dependencies) through Wave 4.
This ensures "depends on" relationships can reference already-created ticket IDs.
(Note: "Wave" here refers to Implementation Waves from the plan, NOT /sprint phases.)

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
{A "ghost dependency" is an existing file that imports from a file this ticket modifies,
but is NOT listed in this ticket's "Files to modify." If the modified function's signature
or behavior changes, the ghost dependency will break silently. List ALL functions this
ticket's code will call or be called by, with exact signatures.}
- `{module}.{function}({params})` → returns {type}, throws on {condition}
- `{module}.{function}({params})` → returns {type}, side effects: {DB write, event emit, etc.}
- Ghost callers (files that import from modified files but aren't in this ticket):
  - `{caller/path.ts}` imports `{functionName}` — will break if signature changes

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

OTHERWISE (mixed conditions — doesn't clearly fit either mode):
  → Default to Agent Teams (safer choice for mixed complexity)
  → Explain which conditions matched each mode:
    "Some tickets have dependencies (→ Agent Teams) but total edge cases are low (→ Subagents).
     Defaulting to Agent Teams for safety. Override in /sprint config if desired."

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
20. **Respect concurrency limits.** Phase 2.5 spawns at most `MAX_PARALLEL_CONTEXT_AGENTS`
    (default: 4) concurrent agents. Group tickets sharing >50% of files into one agent.
21. **Re-enrich after modifications.** If user modifies tickets in Phase 3, re-run
    affected enrichment phases (2.5/2.75) before re-presenting. Cosmetic changes skip re-enrichment.

---

## FLOW DIAGRAM

```
/tickets "{FEATURE}"
    │
    ▼
┌─────────────────────────────────────────┐
│  PHASE 0: PRE-FLIGHT                    │
│  ├── Load problem statement (if exists) │
│  │   ├── Schema + section validation    │
│  │   ├── Staleness check (commit SHA)   │
│  │   └── Extract key fields             │
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
│  ├── Consume ARCHITECTURE_REPORT risks  │
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
│  ├── Problem statement coverage check   │
│  ├── Edge case coverage count           │
│  ├── Dependency validation status       │
│  ├── Complexity changes summary         │
│  ├── Options: create / modify / dry-run │
│  └── If modify → re-enrichment loop     │
│       back to Phase 2.5/2.75 if needed  │
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
| Context Agent (×N) | 2.5 | Sonnet | Deep file reads per ticket — signatures, callers, tests. Output: TICKET_CONTEXT_REPORT (see formal structure in Phase 2.5). Receives problem statement context. | YES |
| Dependency Validator | 2.75B | Sonnet | Import graph analysis, circular dep detection | YES |

**All agents receive ANTI-HALLUCINATION RULES in their prompt. No exceptions.**

**Helper functions used by the orchestrator (not agents):**
- `extract_section(heading, [file])` — Parses markdown sections from problem-statement.md (Phase 0-Pre)
- `extract_nouns_and_key_phrases(text)` — Extracts keywords for coverage matching (Phase 3)

---

## EXECUTION CHECKLIST

Before presenting to user at Phase 3, verify:

```
[ ] Step 0-Pre: Problem statement loaded (if exists)
    [ ] Schema version validated (≥2 expected)
    [ ] Required sections present (Problem, Definition of Done, Testing Strategy, Constraints)
    [ ] Sub-sections present (User Journey, Success Criteria, Implied Features, Codebase Snapshot)
    [ ] Staleness checked (generated_commit vs current HEAD)
    [ ] extract_section() parser available for downstream steps
[ ] Phase 0: Linear MCP connected, git clean, baseline build passes
[ ] Phase 0: progress.txt initialized (or already exists)
[ ] Phase 0: .claude/agent-memory/tickets-explore/ directory created
[ ] Phase 0: .gitignore includes worktrees, sprint-dashboard, sprint-state, problem-statement, sprint-hints
[ ] Phase 1: ARCHITECTURE_REPORT has 0 UNVERIFIED references
[ ] Phase 1: Test infrastructure documented (runner, mocking, fixtures)
[ ] Phase 1: Error patterns documented with examples
[ ] Phase 2: ARCHITECTURE_REPORT risks consumed (assigned to tickets or dedicated risk tickets)
[ ] Phase 2: All tickets within sizing limits
[ ] Phase 2: All tickets have tags (migration/schema/service/component/etc)
[ ] Phase 2.5: TICKET_CONTEXT_REPORT exists for every ticket (matches formal structure)
[ ] Phase 2.5: Context Agents received problem statement context (constraints, testing level)
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
[ ] Phase 3 modification re-enrichment logic ready (if user modifies tickets)
[ ] extract_nouns_and_key_phrases() keyword extraction tested against success criteria
[ ] Ghost dependency callers documented in ticket Caller-Callee Contracts section
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
