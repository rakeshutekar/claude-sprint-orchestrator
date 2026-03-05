#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# sprint-wave.sh — Headless Sprint Runner
# =============================================================================
# Breaks a sprint into discrete, resumable steps. Each step is a separate
# `claude -p` invocation with its own full context window.
#
# Reads config from .claude/sprint-config.yml (per-repo).
# Writes state to .claude/plans/sprint-state.json (resumable).
# Writes learnings to progress.txt (Ralph pattern).
#
# Usage:
#   ./scripts/sprint-wave.sh                         # Run full sprint
#   ./scripts/sprint-wave.sh --resume                # Resume from last state
#   ./scripts/sprint-wave.sh --step preflight        # Run a specific step
#   ./scripts/sprint-wave.sh --dry-run               # Show what would run
#   ./scripts/sprint-wave.sh --status                # Show current state
#   ./scripts/sprint-wave.sh --problem-id auth-flow  # Run for a specific problem
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/.claude/sprint-config.yml"
LOG_DIR="$REPO_ROOT/.claude/logs"
GLOBAL_PROGRESS="$REPO_ROOT/progress.txt"

# Problem directory resolution — called after argument parsing
resolve_problem_dir() {
  local problem_id=""
  if [ -n "${PROBLEM_ID:-}" ]; then
    problem_id="$PROBLEM_ID"
  elif [ -f "$REPO_ROOT/.claude/active-problem" ]; then
    problem_id=$(cat "$REPO_ROOT/.claude/active-problem")
  else
    local dirs=()
    if [ -d "$REPO_ROOT/.claude/sprints" ]; then
      for d in "$REPO_ROOT/.claude/sprints"/*/; do
        [ -d "$d" ] && dirs+=("$d")
      done
    fi
    if [ ${#dirs[@]} -eq 1 ]; then
      problem_id=$(basename "${dirs[0]}")
    elif [ ${#dirs[@]} -eq 0 ] && [ -f "$REPO_ROOT/.claude/sprint-state.json" ]; then
      # Legacy migration
      problem_id="default"
      mkdir -p "$REPO_ROOT/.claude/sprints/default"
      mv "$REPO_ROOT/.claude/sprint-state.json" "$REPO_ROOT/.claude/sprints/default/" 2>/dev/null || true
      [ -f "$REPO_ROOT/.claude/sprint-hints.json" ] && mv "$REPO_ROOT/.claude/sprint-hints.json" "$REPO_ROOT/.claude/sprints/default/" 2>/dev/null || true
      [ -f "$REPO_ROOT/.claude/problem-statement.md" ] && mv "$REPO_ROOT/.claude/problem-statement.md" "$REPO_ROOT/.claude/sprints/default/" 2>/dev/null || true
      echo "default" > "$REPO_ROOT/.claude/active-problem"
      log_info "Migrated legacy sprint files to .claude/sprints/default/"
    else
      log_error "Cannot determine active problem. Set PROBLEM_ID or run /define."
      exit 1
    fi
  fi
  PROBLEM_DIR="$REPO_ROOT/.claude/sprints/$problem_id"
  STATE_FILE="$PROBLEM_DIR/sprint-state.json"
  PROGRESS_FILE="$PROBLEM_DIR/progress.txt"
  TICKETS_FILE="$PROBLEM_DIR/sprint-tickets.json"
  mkdir -p "$PROBLEM_DIR"
  log_info "Problem: $problem_id (dir: $PROBLEM_DIR)"
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Helpers
# =============================================================================

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

timestamp() { date +"%Y-%m-%dT%H:%M:%S"; }

# Parse YAML (basic — no external deps)
parse_yaml() {
  local key="$1"
  grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//'
}

# Read/write sprint state
read_state() {
  local key="$1"
  if [ -f "$STATE_FILE" ]; then
    python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('$key', ''))" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

write_state() {
  local key="$1" value="$2"
  mkdir -p "$(dirname "$STATE_FILE")"
  if [ -f "$STATE_FILE" ]; then
    python3 -c "
import json
d = json.load(open('$STATE_FILE'))
d['$key'] = '$value'
d['updated_at'] = '$(timestamp)'
json.dump(d, open('$STATE_FILE', 'w'), indent=2)
"
  else
    python3 -c "
import json
d = {'$key': '$value', 'created_at': '$(timestamp)', 'updated_at': '$(timestamp)'}
json.dump(d, open('$STATE_FILE', 'w'), indent=2)
"
  fi
}

# Run a claude headless command with logging
run_claude() {
  local step_name="$1"
  local prompt="$2"
  local model="${3:-sonnet}"
  local log_file="$LOG_DIR/${step_name}-$(date +%Y%m%d-%H%M%S).log"

  mkdir -p "$LOG_DIR"

  log_step "Running: $step_name (model: $model)"
  log_info "Log: $log_file"

  if [ "$DRY_RUN" = true ]; then
    log_warn "[DRY RUN] Would run: claude -p \"$prompt\" --model $model"
    return 0
  fi

  # Run claude headless with allowed tools
  claude -p "$prompt" \
    --model "$model" \
    --allowedTools "Edit,Read,Write,Bash,Grep,Glob,Task,WebSearch" \
    2>&1 | tee "$log_file"

  local exit_code=${PIPESTATUS[0]}

  if [ $exit_code -ne 0 ]; then
    log_error "Step $step_name failed (exit: $exit_code). See: $log_file"
    write_state "last_failed_step" "$step_name"
    return $exit_code
  fi

  log_ok "Step $step_name completed"
  write_state "last_completed_step" "$step_name"
  return 0
}

# =============================================================================
# Sprint Steps
# =============================================================================

step_preflight() {
  log_step "═══ PHASE 0: PRE-FLIGHT ═══"

  local branch_base=$(parse_yaml "branch_base")
  local build_cmd=$(parse_yaml "build_cmd")

  run_claude "preflight" "
You are running sprint pre-flight checks. Do these in order and STOP if any fail:

1. Verify Linear MCP is connected (fetch one ticket from team $(parse_yaml 'linear_filter'))
2. git checkout $branch_base && git pull origin $branch_base
3. Run: $build_cmd (must exit 0)
4. Create safety tag: git tag sprint-start-\$(date +%Y%m%d-%H%M%S) $branch_base
5. Ensure .claude/worktrees/ is in .gitignore
6. Initialize progress.txt if it doesn't exist
7. Clean up any stale worktrees from previous sprints

Report: PREFLIGHT_RESULT with pass/fail for each check.
If ALL pass, output: PREFLIGHT_PASS
If ANY fail, output: PREFLIGHT_FAIL with the specific failure.
" "sonnet"

  write_state "phase" "preflight_complete"
}

step_fetch_tickets() {
  log_step "═══ PHASE 1: FETCH TICKETS ═══"

  local team=$(parse_yaml "linear_filter" | head -1)

  run_claude "fetch-tickets" "
Fetch all tickets from Linear matching this filter:
  Team: $(parse_yaml 'linear_filter')

For each ticket, extract: id, title, description, priority, labels.
Save the ticket list as JSON to: .claude/plans/sprint-tickets.json

Format:
{
  \"tickets\": [
    {\"id\": \"CLA-15\", \"title\": \"...\", \"description\": \"...\", \"priority\": 2, \"labels\": [\"...\"]},
    ...
  ],
  \"count\": N,
  \"fetched_at\": \"$(timestamp)\"
}

Output: TICKETS_FETCHED with count.
" "sonnet"

  write_state "phase" "tickets_fetched"
}

step_wave_execute() {
  log_step "═══ PHASE 2+3: WAVE EXECUTION ═══"

  if [ ! -f "$TICKETS_FILE" ]; then
    log_error "No tickets file found at $TICKETS_FILE. Run fetch_tickets first."
    return 1
  fi

  local max_parallel=$(parse_yaml "max_parallel")
  max_parallel=${max_parallel:-4}
  local model_worker=$(python3 -c "
import json
# Parse models from config - default to opus for worker
print('opus')
" 2>/dev/null || echo "opus")

  local ticket_count=$(python3 -c "import json; print(json.load(open('$TICKETS_FILE'))['count'])" 2>/dev/null || echo "0")

  if [ "$ticket_count" -eq 0 ]; then
    log_warn "No tickets to process."
    write_state "phase" "wave_complete"
    return 0
  fi

  log_info "Processing $ticket_count tickets (max $max_parallel parallel)"

  # Ask user: headless or shared context?
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  How should agents share context for this wave?             ║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║                                                             ║${NC}"
  echo -e "${CYAN}║  [1] HEADLESS (Recommended for large sprints)               ║${NC}"
  echo -e "${CYAN}║      Each ticket gets its own claude -p process.            ║${NC}"
  echo -e "${CYAN}║      ✓ Full context window per ticket                       ║${NC}"
  echo -e "${CYAN}║      ✓ Survives context exhaustion                          ║${NC}"
  echo -e "${CYAN}║      ✓ True parallelism (separate processes)                ║${NC}"
  echo -e "${CYAN}║      ✗ No real-time context sharing between agents          ║${NC}"
  echo -e "${CYAN}║      ✗ Learnings shared via progress.txt (async)            ║${NC}"
  echo -e "${CYAN}║                                                             ║${NC}"
  echo -e "${CYAN}║  [2] SHARED CONTEXT (Recommended for <5 tickets)            ║${NC}"
  echo -e "${CYAN}║      Single interactive session runs /sprint command.        ║${NC}"
  echo -e "${CYAN}║      ✓ Real-time context passing between agents             ║${NC}"
  echo -e "${CYAN}║      ✓ Orchestrator can make smart decisions on the fly     ║${NC}"
  echo -e "${CYAN}║      ✗ May hit context exhaustion on large sprints          ║${NC}"
  echo -e "${CYAN}║      ✗ Single point of failure                              ║${NC}"
  echo -e "${CYAN}║                                                             ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local choice=""
  while [[ "$choice" != "1" && "$choice" != "2" ]]; do
    read -rp "Choose mode [1/2]: " choice
  done

  if [ "$choice" = "2" ]; then
    log_info "Launching interactive /sprint session..."
    write_state "mode" "shared_context"
    claude --command sprint
    write_state "phase" "wave_complete"
    return 0
  fi

  write_state "mode" "headless"

  # Headless mode: spawn parallel agents per ticket
  local pids=()
  local running=0

  # Read tickets and spawn agents
  python3 -c "
import json
tickets = json.load(open('$TICKETS_FILE'))['tickets']
for t in tickets:
    print(f\"{t['id']}|{t['title']}|{t['description'][:500]}\")
" | while IFS='|' read -r ticket_id ticket_title ticket_desc; do

    # Wait if at max parallel capacity
    while [ $running -ge $max_parallel ]; do
      wait -n 2>/dev/null || true
      running=$((running - 1))
    done

    log_info "Spawning agent pair for $ticket_id: $ticket_title"

    # Each ticket gets a full context+worker+verify cycle as one headless call
    (
      run_claude "ticket-${ticket_id}" "
You are implementing ticket $ticket_id: \"$ticket_title\".

Read .claude/commands/orchestrate-parallel-sprint.md for the full process.
Follow the EXACT workflow for a single ticket:

1. CONTEXT PHASE: Research the codebase for this ticket. Read progress.txt first.
2. IMPLEMENT: Create an isolated worktree, implement the ticket, follow backpressure rule.
3. VERIFY: Run build, lint, typecheck, tests. Collect evidence.
4. REVIEW: Check security, logic, patterns.
5. COMPLETE: Match requirements line-by-line. Add evidence comment to Linear. Mark Done.

Ticket description:
$ticket_desc

Config:
- Branch: $(parse_yaml 'branch_base')
- Build: $(parse_yaml 'build_cmd')
- Lint: $(parse_yaml 'lint_cmd')
- Test: $(parse_yaml 'test_cmd')
- Typecheck: $(parse_yaml 'typecheck_cmd')
- Standards: $(parse_yaml 'project_standards')

After completing, append learnings to progress.txt.
Output: TICKET_COMPLETE or TICKET_FAILED with details.
" "opus"
    ) &

    pids+=($!)
    running=$((running + 1))

  done

  # Wait for all ticket agents to finish
  log_info "Waiting for all ticket agents to complete..."
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || log_warn "Agent $pid exited with error"
  done

  log_ok "All ticket agents completed"
  write_state "phase" "wave_complete"
}

step_merge() {
  log_step "═══ PHASE 4+5: MERGE + BUILD GATE ═══"

  run_claude "merge" "
You are the merge scheduler and executor.

1. List all worktree branches: git worktree list
2. For each branch starting with 'worktree-', determine the merge order:
   - Dependencies first (services before UI)
   - New-file-only branches first (lowest conflict risk)
   - Higher priority tickets first
3. Merge each branch sequentially into $(parse_yaml 'branch_base'):
   - Create pre-merge tag
   - Merge with --no-ff
   - If conflict: resolve it (read context from progress.txt)
   - Verify build after each merge: $(parse_yaml 'build_cmd')
   - Clean up worktree after successful merge
4. After ALL merges, run full build gate:
   $(parse_yaml 'build_cmd') && $(parse_yaml 'lint_cmd') && $(parse_yaml 'typecheck_cmd') && $(parse_yaml 'test_cmd')
5. If build gate fails: fix and re-run (max $(parse_yaml 'max_loop_iterations') attempts)

Output: MERGE_COMPLETE with summary or MERGE_FAILED with details.
" "opus"

  write_state "phase" "merge_complete"
}

step_e2e() {
  log_step "═══ PHASE 6: E2E BEHAVIORAL VERIFICATION ═══"

  local e2e_cmd=$(parse_yaml "e2e_cmd")

  if [ -z "$e2e_cmd" ]; then
    log_warn "No E2E command configured. Skipping."
    write_state "phase" "e2e_complete"
    return 0
  fi

  run_claude "e2e" "
You are the E2E verification agent. The sprint code has been merged.

1. Start the dev server: npm run dev &
2. Wait for it to be ready
3. Run E2E tests: $e2e_cmd
4. For each completed ticket (read from progress.txt):
   - Verify the feature behaviorally (curl endpoints, check DB, check logs)
5. If ANY test fails, create a new Linear ticket with:
   - Title: 'Fix: {what failed}'
   - Priority: 2 (High)
   - Label: $(parse_yaml 'linear_filter')
   - Full error output and reproduction steps
6. Kill the dev server when done

Output: E2E_PASS or E2E_FAIL with details and new ticket IDs.
" "sonnet"

  write_state "phase" "e2e_complete"
}

step_remaining_check() {
  log_step "═══ PHASE 7: REMAINING TICKET CHECK ═══"

  local iteration=$(read_state "iteration" || echo "0")
  iteration=$((iteration + 1))
  local max_iter=$(parse_yaml "max_loop_iterations")
  max_iter=${max_iter:-3}

  if [ "$iteration" -gt "$max_iter" ]; then
    log_warn "Safety cap reached ($iteration/$max_iter). Manual intervention required."
    write_state "phase" "safety_stopped"
    return 1
  fi

  write_state "iteration" "$iteration"

  run_claude "remaining-check" "
Check Linear for remaining tickets:
  Team: $(parse_yaml 'linear_filter')
  Status: NOT 'Done'

If 0 remaining → output: SPRINT_COMPLETE
If tickets remain → output: TICKETS_REMAINING with count and IDs

Current iteration: $iteration / $max_iter
" "sonnet"

  local phase=$(read_state "phase")
  if [ "$phase" = "sprint_complete" ]; then
    return 0
  fi

  # If tickets remain, loop back to wave execution
  log_info "Remaining tickets found. Starting wave $((iteration + 1))..."
  step_fetch_tickets
  step_wave_execute
  step_merge
  step_e2e
  step_remaining_check
}

step_cleanup() {
  log_step "═══ SPRINT CLEANUP ═══"

  run_claude "cleanup" "
Run sprint cleanup:

1. Remove ALL remaining worktrees:
   git worktree list | grep '.claude/worktrees' and remove each
2. Prune worktree references: git worktree prune
3. Clean up merged worktree branches:
   git branch --list 'worktree-*' — delete if merged, keep if not
4. Final git status and worktree list
5. Generate sprint summary from progress.txt

Output the final sprint report.
" "sonnet"

  write_state "phase" "complete"
  log_ok "Sprint complete!"
}

# =============================================================================
# Main
# =============================================================================

DRY_RUN=false
RESUME=false
SPECIFIC_STEP=""
SHOW_STATUS=false
PROBLEM_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)      DRY_RUN=true; shift ;;
    --resume)       RESUME=true; shift ;;
    --step)         SPECIFIC_STEP="$2"; shift 2 ;;
    --status)       SHOW_STATUS=true; shift ;;
    --problem-id)   PROBLEM_ID="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: sprint-wave.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --resume        Resume from last completed step"
      echo "  --step NAME     Run a specific step (preflight|fetch|wave|merge|e2e|check|cleanup)"
      echo "  --dry-run       Show what would run without executing"
      echo "  --status        Show current sprint state"
      echo "  --problem-id ID Specify which problem to run (default: auto-detect)"
      echo "  -h, --help      Show this help"
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Resolve problem directory (must happen after argument parsing)
resolve_problem_dir

# Check config exists
if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Config not found: $CONFIG_FILE"
  log_info "Create .claude/sprint-config.yml with your project settings."
  exit 1
fi

cd "$REPO_ROOT"

# Show status
if [ "$SHOW_STATUS" = true ]; then
  echo -e "\n${CYAN}═══ Sprint State ═══${NC}"
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE" | python3 -m json.tool 2>/dev/null || cat "$STATE_FILE"
  else
    echo "No active sprint."
  fi
  exit 0
fi

# Run specific step
if [ -n "$SPECIFIC_STEP" ]; then
  case $SPECIFIC_STEP in
    preflight) step_preflight ;;
    fetch)     step_fetch_tickets ;;
    wave)      step_wave_execute ;;
    merge)     step_merge ;;
    e2e)       step_e2e ;;
    check)     step_remaining_check ;;
    cleanup)   step_cleanup ;;
    *) log_error "Unknown step: $SPECIFIC_STEP"; exit 1 ;;
  esac
  exit $?
fi

# Resume from last state
if [ "$RESUME" = true ]; then
  local_phase=$(read_state "phase")
  log_info "Resuming from phase: $local_phase"

  case $local_phase in
    "preflight_complete") step_fetch_tickets; step_wave_execute; step_merge; step_e2e; step_remaining_check; step_cleanup ;;
    "tickets_fetched")    step_wave_execute; step_merge; step_e2e; step_remaining_check; step_cleanup ;;
    "wave_complete")      step_merge; step_e2e; step_remaining_check; step_cleanup ;;
    "merge_complete")     step_e2e; step_remaining_check; step_cleanup ;;
    "e2e_complete")       step_remaining_check; step_cleanup ;;
    "complete")           log_ok "Sprint already complete!"; exit 0 ;;
    *)                    log_warn "Unknown state '$local_phase'. Starting from beginning."; ;&
    "")                   step_preflight; step_fetch_tickets; step_wave_execute; step_merge; step_e2e; step_remaining_check; step_cleanup ;;
  esac
  exit $?
fi

# Full sprint run
echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}       HEADLESS SPRINT RUNNER v1.0                ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "  Config:  $CONFIG_FILE"
echo -e "  Branch:  $(parse_yaml 'branch_base')"
echo -e "  State:   $STATE_FILE"
echo -e "  Logs:    $LOG_DIR"
echo ""

step_preflight
step_fetch_tickets
step_wave_execute
step_merge
step_e2e
step_remaining_check
step_cleanup
