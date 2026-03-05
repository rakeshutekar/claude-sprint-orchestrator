---
description: Validate infrastructure, confirm branch, then execute parallel agent sprint from Linear tickets. Full pipeline with pre/post validation.
---

# Sprint: Validate Infrastructure + Execute Orchestration

Read and execute these two files in sequence:

1. `.claude/commands/test-orchestrate-sprint.md` — infrastructure validation
2. `.claude/commands/orchestrate-parallel-sprint.md` — the orchestration prompt

**Model policy: Use Sonnet 4.6 for all context/review agents. Use Opus 4.6 for all implementation/fix agents. Do NOT use Haiku for any agent in this sprint.**

---

## STEP 0: Branch Confirmation (ALWAYS — NEVER SKIP)

Before doing ANYTHING else, resolve the active problem and confirm the working branch with the user:

### 0A: Resolve Problem Directory

```
RESOLVE PROBLEM DIRECTORY:
  Step 1: If user provided a problem ID as argument ($ARGS) → use it
  Step 2: Else if .claude/active-problem exists → PROBLEM_ID = contents of that file
  Step 3: Else if exactly one directory under .claude/sprints/ → use its name
  Step 4: Else if legacy singleton files exist (.claude/problem-statement.md, .claude/sprint-hints.json, .claude/sprint-state.json) →
          PROBLEM_ID = "default"
          mkdir -p .claude/sprints/default
          Move each legacy file to .claude/sprints/default/
          echo "default" > .claude/active-problem
          Log: "Migrated legacy sprint files to .claude/sprints/default/"
  Step 5: Else → HARD STOP: "No active problem found. Run /define first to create a problem."

  PROBLEM_DIR = .claude/sprints/${PROBLEM_ID}
```

### 0B: Branch Confirmation

```bash
git branch --show-current
git log --oneline -3
```

Then ask the user:

```
You are currently on branch: {branch_name}
Active problem: {PROBLEM_ID} (.claude/sprints/{PROBLEM_ID}/)
Last 3 commits:
  {commit1}
  {commit2}
  {commit3}

Is this the correct branch to run the sprint from?
If not, which branch should I use?
```

**WAIT for the user to confirm the branch before proceeding.**
If the user provides a different branch:
```bash
git checkout {user_specified_branch}
git pull origin {user_specified_branch}
```

Re-confirm after switching:
```
Switched to: {new_branch}. Confirmed?
```

The confirmed branch becomes `BRANCH_BASE` for the entire sprint.
This overrides any BRANCH_BASE in the user's config if they differ.

---

## STEP 1: Infrastructure Validation (BLOCKING)

Run Tests 1-6 from the testing guide:

| Test | What | Must Pass |
|------|------|-----------|
| 1 | Linear MCP connectivity | YES |
| 2 | Worktree .gitignore | YES |
| 3 | Worktree creation via Task tool | YES |
| 4 | Read-only worktree auto-cleanup | YES |
| 5 | Worker commit preservation | YES |
| 6 | Agent resume (fix agent pattern) | YES |

**If ANY test fails → STOP. Report the failure. Do NOT proceed.**

After each test, clean up any test artifacts (worktrees, branches, files).

---

## STEP 2: Execute Orchestration

Only after branch is confirmed AND all 6 infrastructure tests pass,
execute the orchestration prompt with the user's sprint config.

**Use the confirmed branch from Step 0 as BRANCH_BASE — always.**
**Pass PROBLEM_ID and PROBLEM_DIR as context to the orchestrator** so it reads/writes state from the correct problem directory.

If no config is provided, ask the user for:
- LINEAR_FILTER (team, label, status)
- PROJECT_STANDARDS file path
- BUILD_CMD, LINT_CMD, TEST_CMD, TYPECHECK_CMD, E2E_CMD
- MAX_LOOP_ITERATIONS

Note: BRANCH_BASE comes from Step 0 confirmation, not from user config.

### Agent Model Assignment (MANDATORY)

| Agent Role | Model | Rationale |
|------------|-------|-----------|
| Context Agent | **Sonnet 4.6** | Codebase research — fast, thorough |
| Worker Agent | **Opus 4.6** | Implementation — quality matters |
| Code Review Agent | **Sonnet 4.6** | Pattern checking — good balance |
| Fix Agent | **Opus 4.6** | Bug fixing — quality matters |
| Completion Agent | **Sonnet 4.6** | Verification — fast comparison |
| Scheduler Agent | **Sonnet 4.6** | Dependency analysis — fast |
| Conflict Agent | **Opus 4.6** | Merge resolution — needs deep reasoning |
| Build Gate Agent | **Opus 4.6** | Build fixing — quality matters |
| E2E Test Agent | **Sonnet 4.6** | Test writing/running — fast |

**No Haiku. Ever. For any agent in this sprint.**

---

## STEP 3: Post-Sprint Validation

After the orchestration completes, run Tests 7-10 from the testing guide:

| Test | What | Purpose |
|------|------|---------|
| 7 | Parallel agent pairs | Verify parallelism worked |
| 8 | Merge workflow | Verify merges are clean |
| 9 | Linear ticket updates | Verify tickets marked Done |
| 10 | Full integration | Verify end-to-end |

### Final Branch Verification

After all phases complete, confirm the final state:

```bash
git branch --show-current            # Must be BRANCH_BASE
git log --oneline -10                # Show all merge commits from sprint
git status                           # Must be clean
```

Report final sprint summary with:
- Problem: {PROBLEM_ID}
- Branch: {BRANCH_BASE}
- Tickets completed: {N}
- Tickets remaining: {N}
- Total commits: {N}
- Total agents spawned: {N}
