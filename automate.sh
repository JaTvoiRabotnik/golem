#!/bin/bash

# === Configuration ===
# Issues can be passed as arguments, or set here as default
# Usage: ./automate.sh 259 260 261
if [ $# -eq 0 ]; then
  ISSUES=(
    "259"
    # "260"
    # "261"
  )
else
  ISSUES=("$@")
fi

# Log directory
LOG_DIR="./claude-logs"
mkdir -p "$LOG_DIR"

# Timestamp for this run
RUN_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_LOG="$LOG_DIR/run_${RUN_TIMESTAMP}.log"

# === Logging functions ===
log() {
  echo "$1" | tee -a "$RUN_LOG"
}

log_raw() {
  echo "$1" >> "$RUN_LOG"
}

# === Pretty output functions ===
parse_claude_output() {
  local issue_log="$1"
  
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    
    # Always write raw JSON to issue log
    echo "$line" >> "$issue_log"
    
    type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    
    case "$type" in
      system)
        subtype=$(echo "$line" | jq -r '.subtype // empty')
        if [[ "$subtype" == "init" ]]; then
          model=$(echo "$line" | jq -r '.model // "unknown"')
          log "  Model: $model"
        fi
        ;;
      
      assistant)
        text=$(echo "$line" | jq -r '.message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null)
        if [[ -n "$text" ]]; then
          log "  💭 $text"
        fi
        
        tool_name=$(echo "$line" | jq -r '.message.content[]? | select(.type=="tool_use") | .name // empty' 2>/dev/null)
        if [[ -n "$tool_name" ]]; then
          tool_input=$(echo "$line" | jq -r '.message.content[]? | select(.type=="tool_use") | .input // empty' 2>/dev/null)
          
          case "$tool_name" in
            Bash)
              cmd=$(echo "$tool_input" | jq -r '.command // empty')
              desc=$(echo "$tool_input" | jq -r '.description // empty')
              log "  🔧 Bash: $desc"
              log "     $ $cmd"
              ;;
            mcp__github__*)
              short_name=${tool_name#mcp__github__}
              log "  🐙 GitHub: $short_name"
              echo "$tool_input" | jq -r 'to_entries | .[] | "     \(.key): \(.value)"' 2>/dev/null | while read -r detail; do
                log "$detail"
              done
              ;;
            Read|Edit|Write)
              path=$(echo "$tool_input" | jq -r '.path // .file // empty')
              log "  📄 $tool_name: $path"
              ;;
            TodoWrite)
              log "  📋 Updated todo list:"
              echo "$tool_input" | jq -r '.todos[]? | "     [\(.status)] \(.content)"' 2>/dev/null | while read -r todo; do
                log "$todo"
              done
              ;;
            Grep|Glob)
              pattern=$(echo "$tool_input" | jq -r '.pattern // empty')
              log "  🔍 $tool_name: $pattern"
              ;;
            Task)
              desc=$(echo "$tool_input" | jq -r '.description // empty')
              log "  🤖 Spawning agent: $desc"
              ;;
            *)
              log "  🔧 $tool_name"
              ;;
          esac
        fi
        ;;
      
      user)
        result=$(echo "$line" | jq -r '.tool_use_result // empty' 2>/dev/null)
        if [[ -n "$result" && "$result" != "null" ]]; then
          if echo "$result" | jq -e 'type == "object"' >/dev/null 2>&1; then
            stdout=$(echo "$result" | jq -r '.stdout // empty' 2>/dev/null)
            if [[ -n "$stdout" ]]; then
              log "     → $(echo "$stdout" | head -1 | cut -c1-100)"
            fi
          fi
        fi
        
        error=$(echo "$line" | jq -r '.message.content[]? | select(.is_error==true) | .content // empty' 2>/dev/null)
        if [[ -n "$error" ]]; then
          log "     ❌ Error: $(echo "$error" | cut -c1-100)"
        fi
        ;;
    esac
  done
}

# === Main orchestration loop ===
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Claude Code Orchestrator"
log "  Started: $(date)"
log "  Issues to process: ${ISSUES[*]}"
log "  Run log: $RUN_LOG"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

total=${#ISSUES[@]}
current=0
failed=()

for issue in "${ISSUES[@]}"; do
  ((current++))
  
  ISSUE_LOG="$LOG_DIR/issue_${issue}_${RUN_TIMESTAMP}.json"
  
  log ""
  log "╔═══════════════════════════════════════════════════╗"
  log "║  Issue #$issue ($current/$total)"
  log "║  Log: $ISSUE_LOG"
  log "╚═══════════════════════════════════════════════════╝"
  
  # Reset to main
  log "  ⏳ Checking out main and pulling latest..."
  git checkout main --quiet 2>/dev/null
  git pull origin main --quiet 2>/dev/null
  
  # Run Claude Code
  log "  🚀 Starting Claude Code session..."
  log ""
  
  claude --print --verbose --output-format stream-json --dangerously-skip-permissions \
    "Work on GitHub issue #$issue following the instructions in CLAUDE.md." 2>&1 | parse_claude_output "$ISSUE_LOG"
  
  exit_code=${PIPESTATUS[0]}
  
  log ""
  if [ $exit_code -ne 0 ]; then
    log "  ⚠️  Issue #$issue may have failed (exit code: $exit_code)"
    failed+=("$issue")
    
    read -p "  Continue to next issue? [y/N] " -n 1 -r
    echo
    log_raw "  User response: $REPLY"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log "  Stopping orchestrator."
      break
    fi
  else
    log "  ✅ Issue #$issue completed"
  fi
done

# Summary
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Summary"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  Finished: $(date)"
log "  Processed: $current/$total issues"

if [ ${#failed[@]} -gt 0 ]; then
  log "  ⚠️  Issues with potential failures: ${failed[*]}"
else
  log "  ✅ All issues completed successfully"
fi

log ""
log "  Logs saved to: $LOG_DIR/"
log "    - Run summary: $RUN_LOG"
for issue in "${ISSUES[@]}"; do
  if [[ -f "$LOG_DIR/issue_${issue}_${RUN_TIMESTAMP}.json" ]]; then
    log "    - Issue #$issue raw JSON: issue_${issue}_${RUN_TIMESTAMP}.json"
  fi
done
