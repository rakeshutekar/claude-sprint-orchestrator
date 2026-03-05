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

## STEP 1: Permission Mode Selection (ALWAYS — NEVER SKIP, NEVER CACHE)

Before running infra tests or loading the orchestrator, ask the user how they want to handle permission prompts. This must happen early — the orchestrator generates hundreds of tool calls and without pre-configuration the user faces constant "Allow?" prompts.

**Do NOT store or cache the user's choice.** Always ask fresh every sprint — ticket complexity varies.

**Present this prompt:**
```
═══════════════════════════════════════════════════════════════
PERMISSION MODE
═══════════════════════════════════════════════════════════════

A sprint generates hundreds of tool calls (bash, file edits, git)
across dozens of agents. Without permission config, you'll face
constant "Allow?" prompts.

Options:
  [1] Auto-approve sprint commands (Recommended)
      Adds your sprint commands to allowedTools. You'll only be
      prompted for unexpected commands. Safe and practical.

  [2] Skip all permissions (--dangerously-skip-permissions)
      Full autonomous mode. No prompts at all. Fastest, but
      agents can run ANY command without approval.
      Only recommended in isolated environments (Docker/VM).

  [3] Manual approval
      Default permission behavior. You approve every command.
      Only practical for very small sprints (1-2 tickets).

  [4] I've already configured permissions — skip this step

Choose [1/2/3/4]:
═══════════════════════════════════════════════════════════════
```

**WAIT for the user to choose before proceeding.**

**If user chooses [1] — Auto-approve sprint commands:**

Display the exact `allowedTools` configuration for their `.claude/settings.json`:

```
To auto-approve sprint commands, add these to your
.claude/settings.json under "allow":

{
  "permissions": {
    "allow": [
      "Edit",
      "MultiEdit",
      "Write",
      "Bash(npm run build)",
      "Bash(npm run lint)",
      "Bash(npm run test:run)",
      "Bash(npx tsc --noEmit)",
      "Bash(git *)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Bash(agent-browser *)",
      "Bash(curl -sf http://localhost*)"
    ]
  }
}

NOTE: These patterns are derived from YOUR sprint config.
Only the commands you configured above will be auto-approved.
```

Then ask: "Have you added these to your settings? [yes/skip]"

If "yes" → proceed.
If "skip" → proceed with manual permissions (user's choice).

**Important:** The orchestrator does NOT modify `.claude/settings.json` itself.
Modifying security settings programmatically is a boundary the orchestrator must not cross.
The user copies the config manually so they own the decision.

**If user chooses [2] — Skip all permissions:**

```
⚠️  You've chosen to skip all permissions. This means agents can run
ANY command without approval, including potentially destructive operations.

To enable this, start Claude Code with:
  claude --dangerously-skip-permissions

If you're already in a session, you'll need to restart with this flag.
Are you running with --dangerously-skip-permissions? [yes/no]
```

If "yes" → proceed.
If "no" → tell user to restart with the flag, then re-run `/sprint`.

**Safety net for option 2:** Even with permissions skipped, the orchestrator's
own rules still prevent destructive actions (Rule 10: no force pushes,
Rule 18: no git reset --hard on main). These are prompt-level guardrails
that don't depend on the permission system.

**If user chooses [3] — Manual approval:**

```
ℹ️  Manual approval mode. You'll be prompted for each command.
    Tip: Press Shift+Tab during the sprint to toggle auto-accept edits on/off.
    This at least eliminates file edit prompts while keeping bash prompts.

Proceeding...
```

**If user chooses [4] — Already configured:**

```
✅ Skipping permission setup. Proceeding...
```

Store the user's selection as `PERMISSION_MODE` (one of: `auto-approve`, `skip-all`, `manual`, `pre-configured`).
Pass `PERMISSION_MODE` to the orchestrator along with `PROBLEM_ID` and `PROBLEM_DIR`.

---

## STEP 2: Infrastructure Validation (BLOCKING)

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

## STEP 3: Execute Orchestration

Only after branch is confirmed, permission mode is chosen, AND all 6 infrastructure tests pass,
execute the orchestration prompt with the user's sprint config.

**Use the confirmed branch from Step 0 as BRANCH_BASE — always.**
**Pass PROBLEM_ID, PROBLEM_DIR, and PERMISSION_MODE as context to the orchestrator** so it reads/writes state from the correct problem directory and skips its own permission prompt.

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

## STEP 4: Post-Sprint Validation

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
