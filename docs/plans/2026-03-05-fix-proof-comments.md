# Fix Proof Comments: UUID Resolution + Verify-After-Write + Auto-Approve

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure evidence comments are reliably posted to Linear before tickets are marked Done — fixing the 3 root causes that silently prevent comment creation.

**Architecture:** Phase 1 now resolves Linear internal UUIDs at fetch time and stores them alongside identifiers. All downstream MCP calls (`save_comment`, `save_issue`, `get_issue`, `list_comments`) use UUIDs. Layer 5 gains a verify-after-write step matching Layer 5.5's pattern. `sprint.md` allowedTools includes Linear MCP tools so calls aren't silently blocked by permission prompts during unattended sprints.

**Tech Stack:** Claude Code slash commands (Markdown prompts), Linear MCP plugin tools

---

## Issue Analysis

| # | Root Cause | Impact | Fix |
|---|-----------|--------|-----|
| 1 | `{TICKET_ID}` stores identifier ("CLA-15"), not UUID. `save_comment(issueId:)` may require internal UUID. | `save_comment` silently fails or targets nothing | Resolve UUID in Phase 1, use it everywhere |
| 2 | Layer 5 has no verify-after-write. Comment could fail silently but Layer 5 still logs "PASSED" | No proof on Linear, ticket marked Done anyway | Add `list_comments` verification matching Layer 5.5's pattern |
| 3 | `sprint.md` allowedTools missing `mcp__plugin_linear_linear__*` tools | Every MCP call triggers a permission prompt, blocks unattended sprint | Add all 4 Linear MCP tools to allowedTools |

---

### Task 1: Store UUID in Phase 1 — Canonical File

**Files:**
- Modify: `.claude/commands/orchestrate-parallel-sprint.md:1287-1327`

**Step 1: Update ticket extraction to capture both identifier and UUID**

At line 1292-1293, change:

```
For each ticket, extract:
  - id (Linear issue ID, e.g., "CLA-15")
  - title
  - description (full markdown body)
  - priority (1=urgent, 2=high, 3=medium, 4=low)
  - labels
  - assignee (optional)
```

To:

```
For each ticket, extract:
  - identifier (Linear display ID, e.g., "CLA-15") — used for logs and display
  - uuid (Linear internal UUID) — used for ALL MCP API calls
  - title
  - description (full markdown body)
  - priority (1=urgent, 2=high, 3=medium, 4=low)
  - labels
  - assignee (optional)

NOTE: The Linear MCP `list_issues` / `get_issue` response includes both:
  - `identifier`: the human-readable ID like "CLA-15"
  - `id`: the internal UUID like "a1b2c3d4-..."
Store BOTH. Use `identifier` for logging/display. Use `uuid` for ALL MCP tool calls
(save_comment, save_issue, get_issue, list_comments).
```

**Step 2: Update sprint-state.json initialization to store both**

At line 1312, change:

```
for each ticket in TICKETS[]:
    sprint-state.json.tickets[ticket.id] = {
        "title": ticket.title,
```

To:

```
for each ticket in TICKETS[]:
    sprint-state.json.tickets[ticket.identifier] = {
        "uuid": ticket.uuid,          # Internal UUID — ALL MCP calls use this
        "identifier": ticket.identifier,  # Display ID (e.g., "CLA-15") — logs only
        "title": ticket.title,
```

**Step 3: Verify the change**

Search the file for any remaining `ticket.id` references that should now be `ticket.identifier` or `ticket.uuid`. The key used for `sprint-state.json.tickets[...]` can stay as identifier (it's just a dictionary key for human readability), but all MCP tool call parameters must use `ticket.uuid`.

**Step 4: Commit**

```bash
# Don't commit yet — batch with remaining changes in this task
```

---

### Task 2: Update ALL MCP calls to use UUID — Canonical File

**Files:**
- Modify: `.claude/commands/orchestrate-parallel-sprint.md` (lines 2743, 2998, 3005, 3019, 3023, 3028, 3030)

Every MCP call currently uses `{TICKET_ID}` which resolves to the identifier. Replace with `{TICKET_UUID}` (read from `sprint-state.json.tickets[{TICKET_ID}].uuid`).

**Step 1: Add UUID resolution comment before Layer 5**

Before line 2954, add:

```
        # ─── Resolve UUID for MCP calls ───
        # TICKET_ID is the display identifier (e.g., "CLA-15") used in logs.
        # TICKET_UUID is the internal Linear UUID used for ALL MCP API calls.
        TICKET_UUID = sprint-state.json.tickets[{TICKET_ID}].uuid
```

**Step 2: Update Layer 5 (save_comment calls)**

Line 2998, change:
```
post_result = ORCHESTRATOR calls Linear MCP save_comment(issueId: {TICKET_ID}, body: evidence_comment)
```
To:
```
post_result = ORCHESTRATOR calls Linear MCP save_comment(issueId: {TICKET_UUID}, body: evidence_comment)
```

Line 3005, change:
```
post_result = ORCHESTRATOR retries Linear MCP save_comment(issueId: {TICKET_ID}, body: evidence_comment)
```
To:
```
post_result = ORCHESTRATOR retries Linear MCP save_comment(issueId: {TICKET_UUID}, body: evidence_comment)
```

**Step 3: Update Layer 5.5 (save_issue + get_issue calls)**

Line 3019, change:
```
ORCHESTRATOR calls Linear MCP save_issue(id: {TICKET_ID}, state: "Done")
```
To:
```
ORCHESTRATOR calls Linear MCP save_issue(id: {TICKET_UUID}, state: "Done")
```

Line 3023, change:
```
ticket_status = ORCHESTRATOR calls Linear MCP get_issue(id: {TICKET_ID}) → status
```
To:
```
ticket_status = ORCHESTRATOR calls Linear MCP get_issue(id: {TICKET_UUID}) → status
```

Line 3028, change:
```
ORCHESTRATOR calls Linear MCP save_issue(id: {TICKET_ID}, state: "Done")
```
To:
```
ORCHESTRATOR calls Linear MCP save_issue(id: {TICKET_UUID}, state: "Done")
```

Line 3030, change:
```
ticket_status = ORCHESTRATOR fetches {TICKET_ID} status via Linear MCP
```
To:
```
ticket_status = ORCHESTRATOR calls Linear MCP get_issue(id: {TICKET_UUID}) → status
```

**Step 4: Update circuit breaker save_comment (line 2743)**

Line 2743 (the stuck ticket comment):
```
ORCHESTRATOR calls Linear MCP save_comment(issueId: {TICKET_ID}, body: "## Stuck — ...")
```
To:
```
TICKET_UUID = sprint-state.json.tickets[{TICKET_ID}].uuid
ORCHESTRATOR calls Linear MCP save_comment(issueId: {TICKET_UUID}, body: "## Stuck — ...")
```

**Step 5: Update the max-loops comment at line ~2648**

The `add Linear comment:` call at the end of the loop logic also needs UUID:
```
ORCHESTRATOR calls Linear MCP save_comment(issueId: {TICKET_UUID}, body: "## Max Verification Loops Reached\n...")
```

**Step 6: Update Compaction Recovery Protocol MCP calls (lines 2715-2770)**

All `ORCHESTRATOR fetches {TICKET_ID} status via Linear MCP` and `save_issue(id: {TICKET_ID}, ...)` calls in the recovery section need the same UUID pattern:

```
TICKET_UUID = sprint-state.json.tickets[{TICKET_ID}].uuid
```

Then use `{TICKET_UUID}` in all MCP calls within the recovery block.

**Keep `{TICKET_ID}` in all LOG statements** — those are for human readability.

---

### Task 3: Add Verify-After-Write to Layer 5 — Canonical File

**Files:**
- Modify: `.claude/commands/orchestrate-parallel-sprint.md:3013` (after current Layer 5 "PASSED" log)

**Step 1: Insert verification block after comment post**

Replace lines 3013 (the current "Layer 5 PASSED" log) with a full verify-after-write block:

```
        # ─── Layer 5 VERIFY: Confirm comment actually exists on Linear ───
        # Mirror Layer 5.5's verify pattern: write → wait → read → confirm
        WAIT 2 seconds  # Give Linear API time to propagate

        comments = ORCHESTRATOR calls Linear MCP list_comments(issueId: {TICKET_UUID})
        evidence_found = any comment in comments where body contains "## Implementation Complete"

        if NOT evidence_found:
            LOG ERROR: "LAYER 5 VERIFY FAILED: Comment posted but not found on Linear for {TICKET_ID}"
            # Retry: post again and re-verify
            WAIT 3 seconds
            post_result = ORCHESTRATOR calls Linear MCP save_comment(issueId: {TICKET_UUID}, body: evidence_comment)
            WAIT 2 seconds
            comments = ORCHESTRATOR calls Linear MCP list_comments(issueId: {TICKET_UUID})
            evidence_found = any comment in comments where body contains "## Implementation Complete"

            if NOT evidence_found:
                LOG ERROR: "LAYER 5 VERIFY RETRY FAILED — evidence comment missing after 2 attempts"
                last_error = { type: "evidence_not_verified", message: "Comment posted but not retrievable from Linear" }
                ticket_state = "stuck"
                update sprint-state.json: tickets[{TICKET_ID}].status = "stuck"
                break

        LOG: "Layer 5 PASSED: Evidence comment posted AND VERIFIED on Linear for {TICKET_ID}"
```

This replaces the old single-line log at 3013:
```
LOG: "Layer 5 PASSED: Evidence comment posted to Linear by ORCHESTRATOR for {TICKET_ID}"
```

---

### Task 4: Add Linear MCP Tools to allowedTools — sprint.md

**Files:**
- Modify: `.claude/commands/sprint.md:124-137`

**Step 1: Add Linear MCP tools to the allow list**

Change lines 124-137 from:

```json
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
```

To:

```json
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
      "Bash(curl -sf http://localhost*)",
      "mcp__plugin_linear_linear__save_comment",
      "mcp__plugin_linear_linear__save_issue",
      "mcp__plugin_linear_linear__get_issue",
      "mcp__plugin_linear_linear__list_comments",
      "mcp__plugin_linear_linear__list_issues"
    ]
  }
}
```

**Why `list_issues`:** Phase 1 fetches tickets via `list_issues`. Without auto-approve, even the initial fetch blocks on a permission prompt.

---

### Task 5: Apply Same UUID + Verify Changes to Root Copy

**Files:**
- Modify: `orchestrate-parallel-sprint.md` (root copy, lines 1141-1142, 1312, 2590, 2597, 2605, 2609, 2613, 2618, 2620, 2628, 2632-2636, 2715-2770, 2743)

Apply the exact same changes from Tasks 1-3 to the root copy:
1. Phase 1 ticket extraction: add `identifier` + `uuid` (line 1141-1142)
2. sprint-state init: add `uuid` field (line 1312)
3. All MCP calls: use `{TICKET_UUID}` instead of `{TICKET_ID}` (lines 2590, 2597, 2609, 2613, 2618, 2620, 2715-2770, 2743)
4. Layer 5 verify-after-write block: insert after line 2605

---

### Task 6: Sync to Global and capsure-mvp

**Step 1: Copy files to global ~/.claude/commands/**

```bash
cp .claude/commands/orchestrate-parallel-sprint.md ~/.claude/commands/
cp .claude/commands/sprint.md ~/.claude/commands/
cp .claude/commands/sprint-resume.md ~/.claude/commands/
```

**Step 2: Copy to capsure-mvp (if it exists)**

```bash
if [ -d ~/capsure-mvp/.claude/commands ]; then
  cp .claude/commands/orchestrate-parallel-sprint.md ~/capsure-mvp/.claude/commands/
  cp .claude/commands/sprint.md ~/capsure-mvp/.claude/commands/
  cp .claude/commands/sprint-resume.md ~/capsure-mvp/.claude/commands/
fi
```

**Step 3: Verify sync**

```bash
diff .claude/commands/orchestrate-parallel-sprint.md ~/.claude/commands/orchestrate-parallel-sprint.md
diff .claude/commands/sprint.md ~/.claude/commands/sprint.md
```

---

### Task 7: Commit and Push

**Step 1: Stage and commit**

```bash
git add .claude/commands/orchestrate-parallel-sprint.md
git add .claude/commands/sprint.md
git add orchestrate-parallel-sprint.md
git commit -m "fix: resolve 3 root causes preventing proof comments on Linear

- Store Linear internal UUIDs in Phase 1, use for all MCP API calls
- Add verify-after-write to Layer 5 (list_comments after save_comment)
- Add Linear MCP tools to allowedTools for unattended sprint execution"
```

**Step 2: Push**

```bash
git push
```

---

## Verification Checklist

After implementation, grep the codebase to confirm:

- [ ] No `save_comment(issueId: {TICKET_ID}` left — all should use `{TICKET_UUID}`
- [ ] No `save_issue(id: {TICKET_ID}` left — all should use `{TICKET_UUID}`
- [ ] No `get_issue(id: {TICKET_ID}` left — all should use `{TICKET_UUID}`
- [ ] `list_comments` appears in Layer 5 verify block in BOTH files
- [ ] `sprint.md` allowedTools contains all 5 Linear MCP tools
- [ ] `{TICKET_ID}` still used in LOG statements (human-readable)
- [ ] `sprint-state.json` schema includes `uuid` field
- [ ] Global and capsure-mvp copies are identical to repo copies
