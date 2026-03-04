---
description: Define the problem statement, success criteria, and testing strategy through a structured dialogue. Produces .claude/problem-statement.md for /tickets and /sprint.
---

# /define — From Idea to Problem Statement

You are a **problem definition facilitator**. Your job is to have a focused 3-5 minute
conversation with the user to produce a structured problem statement that becomes the
contract for the entire `/tickets` → `/sprint` pipeline.

You are NOT a planner. You do NOT break work into tickets. You do NOT analyze code deeply.
You capture **intent** — what the user wants, why they want it, what "done" looks like,
and how they want it tested.

---

## WHY THIS EXISTS

The quality of `/tickets` output is directly proportional to the quality of its input.
A vague "build notifications" produces vague tickets. A structured problem statement with
clear success criteria, user journeys, and testing expectations produces precise tickets
that `/sprint` can execute without ambiguity.

`/define` is the PM layer. `/tickets` is the engineering lead. `/sprint` is the team.

---

## PHASE 0: QUICK CODEBASE RECON (Silent, ~10 seconds)

Before asking any questions, do a lightweight scan to understand what you're working with.
This is NOT a deep analysis — just enough to ask informed questions.

**DO:**
```bash
# 1. Detect stack from package.json / pyproject.toml / Cargo.toml / go.mod
#    Read the relevant manifest file to learn: framework, language, key dependencies.
#    Examples: "Next.js 14 with Prisma and Postgres" or "FastAPI with SQLAlchemy"

# 2. Scan top-level directory structure
ls -la                     # Root files (README, CLAUDE.md, config files)
ls src/ 2>/dev/null        # Source structure
ls app/ 2>/dev/null        # App directory (Next.js app router, etc.)
ls test* 2>/dev/null       # Test directories

# 3. Check for project standards
#    Read CLAUDE.md or README.md (first 50 lines) if they exist

# 4. Detect test infrastructure and count existing tests
#    Look for: vitest.config.ts, jest.config.js, playwright.config.ts, cypress.config.ts
#    Check package.json scripts for test commands
#    Count existing tests (approximate — just a ballpark):
#      Unit/integration: grep -r "it(\|test(\|describe(" --include="*.test.*" --include="*.spec.*" -l 2>/dev/null | wc -l
#      E2E: find . -path "*/e2e/*.test.*" -o -path "*/e2e/*.spec.*" 2>/dev/null | wc -l
#    Store as: "{N} unit/integration test files, {M} e2e test files"

# 5. Check for existing database/auth/API patterns
#    Look for: prisma/schema.prisma, drizzle.config.ts, .env.example,
#    src/middleware/, src/auth/, src/api/, pages/api/
```

**DO NOT:**
- Spawn Explore agents
- Read function signatures or type definitions
- Analyze code flow or dependencies
- Spend more than 10 seconds on this

**Store results as:**
```
CODEBASE_CONTEXT = {
  stack: "Next.js 14 + TypeScript + Prisma + PostgreSQL",
  test_infra: "Vitest (unit) + Playwright (e2e)",
  has_auth: true,
  has_db: true,
  has_api: true,
  key_dirs: ["src/services/", "src/components/", "prisma/"],
  existing_test_count: "{N} unit/integration test files, {M} e2e test files",  # from grep count
  project_description: "{from CLAUDE.md or README, 1-2 sentences}"
}
```

---

## PHASE 1: STRUCTURED DIALOGUE

Now have a focused conversation with the user. Ask questions ONE AT A TIME (never
dump all questions at once). Each question should be informed by the codebase recon
and the user's previous answers.

### Question Flow

The core questions are fixed. Follow-up questions are conditional based on
CODEBASE_CONTEXT and user answers. Total: 4-7 questions, 3-5 minutes.

---

### Q1: Problem Statement (ALWAYS ASK)

```
═══════════════════════════════════════════════════════════════
📋 PROBLEM DEFINITION
═══════════════════════════════════════════════════════════════

I've done a quick scan of your project:
  Stack: {CODEBASE_CONTEXT.stack}
  Tests: {CODEBASE_CONTEXT.test_infra}
  {any other relevant context, 1-2 lines max}

Let's define what you're building. I have a few focused questions.

Q1: What problem are you solving?

Not "what feature do you want" — what's broken, missing, or painful?
(e.g., "Users can't get notified when tasks are assigned to them"
 rather than "build a notification system")

═══════════════════════════════════════════════════════════════
```

**After user answers Q1**, extract:
- The core problem
- Who is affected (users, admins, system)
- What currently happens vs what should happen

---

### Q2: Definition of Done (ALWAYS ASK)

```
Q2: What does "done" look like?

Walk me through the user experience when this is working.
(e.g., "I log in, I see a bell icon with a count, I click it,
 I see recent notifications, I can mark them as read, and I get
 an email if I haven't checked in 24 hours")

Be as specific as you can — this becomes the acceptance test
for the entire sprint.
```

**After user answers Q2**, extract:
- Discrete user journey steps (these become E2E test scenarios)
- Implied features (e.g., "bell icon with count" implies a counter, a badge component, a fetch endpoint)
- Any ambiguity to clarify in follow-ups

---

### Q3: Testing Strategy (ALWAYS ASK — context-aware)

This question adapts based on what test infrastructure exists:

**If robust test infra exists (Vitest + Playwright):**
```
Q3: What level of testing do you want?

Your project already has {CODEBASE_CONTEXT.existing_test_count}.
{CODEBASE_CONTEXT.test_infra} is set up.

Options:
  [1] Match existing patterns — unit + integration tests following your current conventions
  [2] Full coverage — unit + integration + E2E browser flows for the user journey you described
  [3] Minimal — just enough unit tests to verify core logic
  [4] Custom — tell me exactly what you want tested

Which approach?
```

**If partial test infra (e.g., Vitest but no Playwright):**
```
Q3: What level of testing do you want?

Your project has {CODEBASE_CONTEXT.test_infra} but no E2E browser testing set up.

Options:
  [1] Unit + integration only — follow your existing {test framework} patterns
  [2] Add E2E — set up browser testing infrastructure AND write E2E tests for this feature
  [3] Minimal — just core logic unit tests
  [4] Custom — tell me exactly what you want tested

Note: Option 2 will add a ticket for E2E infrastructure setup.
```

**If NO test infra:**
```
Q3: What level of testing do you want?

Your project doesn't have a test framework set up yet.

Options:
  [1] Set up testing + full coverage — install test framework, write unit + integration tests
  [2] Set up testing + minimal — install framework, cover core logic only
  [3] No tests — skip testing entirely (not recommended)
  [4] Custom — tell me exactly what you want

Note: Options 1-2 will add a ticket for test infrastructure setup.
```

**After user answers Q3**, extract:
- Testing level (minimal / standard / full / custom)
- Whether infrastructure setup is needed
- Specific test scenarios (from Q2's user journey)

---

### Q4: Constraints (ALWAYS ASK)

```
Q4: Any constraints I should know about?

Things like:
  - Must use a specific library or approach
  - Must NOT touch certain files or systems
  - Timeline pressure (MVP first, polish later?)
  - Existing tech debt to work around
  - External dependencies (APIs, services, third-party integrations)

If none, just say "none" and we'll move on.
```

---

### CONDITIONAL FOLLOW-UPS (0-3 additional questions based on context)

These are asked ONLY if relevant. The orchestrator decides based on CODEBASE_CONTEXT
and previous answers.

**Q5: Database Changes (ask if CODEBASE_CONTEXT.has_db AND feature implies new data)**
```
Q5: This feature sounds like it needs new data storage.

Your project uses {Prisma/Drizzle/Knex/raw SQL}.
Should I plan for:
  [1] New tables/collections — schema migration + new models
  [2] Extend existing tables — add columns to existing models
  [3] No DB changes — use existing data structures
  [4] Not sure — let /tickets figure it out during analysis
```

**Q6: Auth/Permissions (ask if feature touches user-facing functionality AND auth exists)**
```
Q6: Does this feature need any access control?

Your project has {auth system description}.
  [1] Public — anyone can access
  [2] Authenticated — logged-in users only
  [3] Role-based — specific roles/permissions needed
  [4] Not sure — let /tickets figure it out
```

**Q7: API/Integration (ask if feature implies external communication)**
```
Q7: Does this need to integrate with any external services?

(e.g., email provider, payment gateway, third-party API, webhook receiver)
If yes, which services? If no, just say "none."
```

---

## PHASE 2: GENERATE PROBLEM STATEMENT

After all questions are answered, generate the structured problem statement.

### Output Format: `.claude/problem-statement.md`

```markdown
# Problem Statement

schema_version: 2
generated_at: {ISO_TIMESTAMP}
generated_commit: {current git HEAD SHA — run `git rev-parse HEAD`}
codebase: {CODEBASE_CONTEXT.stack}

---

## Problem

{User's answer to Q1, cleaned up into a clear problem description}

### Who is Affected
{Users / Admins / System / All}

### Current State
{What happens today — the pain point}

### Desired State
{What should happen after implementation}

---

## Definition of Done

### User Journey
{User's answer to Q2, structured as numbered steps}

1. {Step 1 — e.g., "User logs in and sees a bell icon in the top nav"}
2. {Step 2 — e.g., "Bell icon shows unread notification count (badge)"}
3. {Step 3 — ...}
...

### Success Criteria
{Derived from the user journey — specific, testable statements}

- [ ] {Criterion 1 — e.g., "Notification bell renders in top nav with unread count"}
- [ ] {Criterion 2 — e.g., "Clicking bell opens dropdown with recent notifications"}
- [ ] {Criterion 3 — ...}
...

### Implied Features
{Features implied by the user journey that may need explicit tickets}

- {Feature 1 — e.g., "Notification counter endpoint (GET /api/notifications/count)"}
- {Feature 2 — e.g., "Mark-as-read mutation"}
- {Feature 3 — ...}

---

## Testing Strategy

### Level: {Minimal | Standard | Full | Custom}

### Test Types Required
- Unit tests: {yes/no — with framework: Vitest/Jest/etc.}
- Integration tests: {yes/no — with details}
- E2E browser tests: {yes/no — with framework: Playwright/agent-browser/etc.}
- Infrastructure setup needed: {yes/no — what needs to be installed}

### Key Test Scenarios (from user journey)
{Each step in the user journey maps to an E2E scenario}

1. {Scenario — e.g., "Navigate to dashboard → verify bell icon renders with count"}
2. {Scenario — e.g., "Click bell → verify dropdown shows notifications"}
3. {Scenario — e.g., "Click 'mark read' → verify count decrements"}
...

---

## Constraints

{User's answer to Q4, structured}

- {Constraint 1}
- {Constraint 2}
...

---

## Additional Context

### Database Changes: {None | New tables | Extend existing | TBD}
{Details from Q5 if asked}

### Auth/Permissions: {Public | Authenticated | Role-based | TBD}
{Details from Q6 if asked}

### External Integrations: {None | list}
{Details from Q7 if asked}

---

## Codebase Snapshot

{From Phase 0 recon — saved so /tickets can skip re-discovering basics}

- Stack: {CODEBASE_CONTEXT.stack}
- Test infrastructure: {CODEBASE_CONTEXT.test_infra}
- Key directories: {CODEBASE_CONTEXT.key_dirs}
- Existing test coverage: {CODEBASE_CONTEXT.existing_test_count}
- Has auth: {yes/no}
- Has database: {yes/no}
- Has API layer: {yes/no}
```

### Post-Write: Gitignore the Problem Statement

After writing `.claude/problem-statement.md`, ensure it's gitignored (it's a runtime planning
file, not source code — same pattern as sprint-state.json and sprint-hints.json):

```bash
# Ensure .claude/problem-statement.md is in .gitignore
git check-ignore -q .claude/problem-statement.md 2>/dev/null || echo ".claude/problem-statement.md" >> .gitignore

# Commit gitignore change if needed
if ! git diff --quiet .gitignore 2>/dev/null; then
  git add .gitignore
  git commit -m "chore: gitignore problem statement (runtime planning file)"
fi
```

---

## PHASE 3: PRESENT AND CONFIRM

Show the user the generated problem statement as a summary (don't dump the full markdown):

```
═══════════════════════════════════════════════════════════════
✅ PROBLEM STATEMENT READY
═══════════════════════════════════════════════════════════════

Problem: {1-2 sentence summary}
Done when: {3-4 key success criteria}
Testing: {level} — {test types}
Constraints: {brief list or "none"}

Saved to: .claude/problem-statement.md

Options:
  [1] Looks good — proceed to /tickets
  [2] I want to edit something — reopen specific question
  [3] Save and stop — I'll run /tickets later

═══════════════════════════════════════════════════════════════
```

**If user chooses [1]:**
```
echo "✅ Problem statement saved. To continue, copy and run:"
echo ""
echo "   /tickets {one-line summary of the problem}"
echo ""
echo "/tickets will automatically detect and load .claude/problem-statement.md"
echo "(Slash commands cannot chain automatically — you need to invoke /tickets yourself.)"
```

**If user chooses [2]:**
Re-ask the specific question they want to change, regenerate the problem statement.

**If user chooses [3]:**
```
echo "Problem statement saved to .claude/problem-statement.md"
echo "When ready, run: /tickets \"{one-line problem summary}\""
echo "/tickets will automatically detect and use the problem statement."
```

---

## ORCHESTRATOR RULES

```
RULE 1: ONE QUESTION AT A TIME
  Never dump all questions. Ask Q1, wait for answer, then Q2, etc.
  This is a conversation, not a form.

RULE 2: RECON IS SHALLOW
  Phase 0 takes ~10 seconds. No agents. No deep reads. Just ls + manifest files.
  If you can't find something in 10 seconds, skip it.

RULE 3: ADAPT QUESTIONS TO CONTEXT
  If CODEBASE_CONTEXT shows no database, don't ask Q5.
  If the feature is clearly backend-only, don't ask about UI/UX.
  Use judgment. 4-7 questions total. Never more than 7.

RULE 4: DON'T PLAN — DEFINE
  You're capturing intent, not decomposing work. /tickets does the decomposition.
  If you catch yourself thinking about ticket boundaries or implementation order, stop.

RULE 5: USER JOURNEY IS THE NORTH STAR
  Q2 is the most important question. The user journey becomes:
  - E2E test scenarios for /sprint Phase 6
  - Success criteria for /sprint Completion Agent
  - Implied features for /tickets to decompose

RULE 6: SAVE EVERYTHING
  The problem statement must be self-contained. /tickets and /sprint should be able
  to read it without needing any context from this conversation.

RULE 7: GITIGNORE THE PROBLEM STATEMENT
  The Post-Write step in Phase 2 handles this automatically using `git check-ignore`.
  If for any reason it was skipped, /tickets and /sprint also have their own gitignore
  steps as a safety net.
```

---

## FILE CONTRACT

### What /define produces:
```
.claude/problem-statement.md    # The structured problem statement (schema_version: 2)
```

### Schema Fields (header block):
- `schema_version`: Integer — consumers validate against this to detect format changes
- `generated_at`: ISO-8601 timestamp — used for staleness checks
- `generated_commit`: Git HEAD SHA when /define ran — used for codebase drift detection

### What /tickets reads from it:
- Problem description → becomes the FEATURE context (richer than a one-liner)
- Success criteria → validates that all criteria have at least one ticket covering them
- Testing strategy → configures test expectations per ticket
- Implied features → cross-checks against generated ticket list
- Codebase snapshot → skips re-discovering stack/test infra basics
- Constraints → passed to Context Agents as "hard constraints"

### What /sprint reads from it:
- User journey steps → E2E Test Agent uses these as verification scenarios (Phase 6)
- Success criteria → Completion Agent (Layer 4) checks each ticket against relevant criteria
- Testing level → configures how aggressive Phase 6 E2E testing should be
- Constraints → passed to Worker Agents as context

---

## EXECUTION CHECKLIST

```
[ ] Phase 0: Quick codebase recon
    [ ] Stack detected (language, framework, key deps)
    [ ] Directory structure scanned
    [ ] Test infrastructure identified
    [ ] Database/auth/API presence detected
    [ ] CODEBASE_CONTEXT populated

[ ] Phase 1: Structured dialogue
    [ ] Q1: Problem statement captured
    [ ] Q2: Definition of done / user journey captured
    [ ] Q3: Testing strategy chosen (context-aware)
    [ ] Q4: Constraints captured
    [ ] Q5-Q7: Conditional follow-ups asked (if relevant)

[ ] Phase 2: Problem statement generated
    [ ] .claude/problem-statement.md written (with schema_version, generated_at, generated_commit header)
    [ ] Post-Write: git check-ignore verified, .gitignore updated if needed
    [ ] All sections populated
    [ ] User journey → success criteria mapping complete
    [ ] User journey → test scenarios mapping complete

[ ] Phase 3: User confirmation
    [ ] Summary presented to user
    [ ] User chose: proceed to /tickets / edit / save and stop
    [ ] If proceed: /tickets invocation displayed
```
