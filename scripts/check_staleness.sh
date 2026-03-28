#!/bin/bash
# check_staleness.sh — Detect CLI changes that might make skill references stale
#
# How it works:
# 1. Captures --help output from each service CLI
# 2. Compares against stored snapshots
# 3. Reports which CLIs have changed (flags added/removed/renamed)
#
# Usage:
#   ./check_staleness.sh                # Compare against snapshots
#   ./check_staleness.sh --snapshot     # Create/update snapshots (baseline)
#   ./check_staleness.sh --report       # Generate detailed diff report
#
# Run with --snapshot first to establish a baseline, then periodically
# run without flags to check for changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_DIR="${SCRIPT_DIR}/../.cli-snapshots"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="${1:---compare}"

# Define CLIs to track and their help commands
# Format: "name|command|subcommands_to_check"
# Each subcommand's --help output is captured separately
TRACKED_CLIS=(
  "supabase|supabase|db,migration,functions,projects,secrets,login"
  "vercel|vercel|env,domains,deploy,project"
  "stripe|stripe|products,prices,webhook_endpoints,listen,login"
  "wrangler|wrangler|pages,d1,r2,kv,secret,deploy"
  "firebase|firebase|deploy,init,functions,hosting,firestore,auth"
  "gh|gh|api,auth,repo,issue,release"
  "neonctl|neonctl|databases,branches,connection-string"
)

capture_help() {
  local cli_name="$1"
  local cli_cmd="$2"
  local subcommands="$3"
  local output_dir="$4"

  mkdir -p "$output_dir"

  # Capture main help
  if command -v "$cli_cmd" &> /dev/null; then
    $cli_cmd --help 2>&1 > "$output_dir/${cli_name}.help" || true

    # Capture version
    $cli_cmd --version 2>&1 > "$output_dir/${cli_name}.version" || true

    # Capture subcommand help
    IFS=',' read -ra SUBS <<< "$subcommands"
    for sub in "${SUBS[@]}"; do
      $cli_cmd "$sub" --help 2>&1 > "$output_dir/${cli_name}_${sub}.help" 2>/dev/null || true
    done

    return 0
  else
    echo "NOT_INSTALLED" > "$output_dir/${cli_name}.help"
    return 1
  fi
}

snapshot() {
  echo -e "${CYAN}Creating CLI snapshots...${NC}"
  echo ""

  local timestamp=$(date '+%Y-%m-%d_%H%M%S')
  local snap_dir="${SNAPSHOT_DIR}/current"

  # Backup previous snapshot
  if [ -d "$snap_dir" ]; then
    mv "$snap_dir" "${SNAPSHOT_DIR}/previous_${timestamp}"
    echo "  Previous snapshot backed up to previous_${timestamp}"
  fi

  mkdir -p "$snap_dir"

  local installed=0
  local missing=0

  for entry in "${TRACKED_CLIS[@]}"; do
    IFS='|' read -r name cmd subs <<< "$entry"

    if capture_help "$name" "$cmd" "$subs" "$snap_dir"; then
      version=$(cat "$snap_dir/${name}.version" 2>/dev/null | head -1)
      echo -e "  ${GREEN}✅${NC} $name ($version)"
      installed=$((installed + 1))
    else
      echo -e "  ${YELLOW}⚠️${NC}  $name — not installed (skipped)"
      missing=$((missing + 1))
    fi
  done

  # Save metadata
  cat > "$snap_dir/metadata.json" << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "hostname": "$(hostname)",
  "clis_tracked": ${#TRACKED_CLIS[@]},
  "clis_installed": $installed,
  "clis_missing": $missing
}
EOF

  echo ""
  echo -e "${GREEN}Snapshot saved to ${snap_dir}${NC}"
  echo "  Tracked: ${#TRACKED_CLIS[@]} CLIs | Installed: $installed | Missing: $missing"
}

compare() {
  local snap_dir="${SNAPSHOT_DIR}/current"

  if [ ! -d "$snap_dir" ]; then
    echo -e "${RED}No snapshot found. Run with --snapshot first to create a baseline.${NC}"
    exit 1
  fi

  echo -e "${CYAN}Checking CLIs against stored snapshots...${NC}"
  echo ""

  local snap_date=$(cat "$snap_dir/metadata.json" 2>/dev/null | grep timestamp | sed 's/.*": "//;s/".*//')
  echo "  Snapshot date: $snap_date"
  echo ""

  local changed=0
  local unchanged=0
  local new_missing=0
  local tmp_dir=$(mktemp -d)

  for entry in "${TRACKED_CLIS[@]}"; do
    IFS='|' read -r name cmd subs <<< "$entry"

    # Skip if wasn't installed at snapshot time
    if [ "$(cat "$snap_dir/${name}.help" 2>/dev/null)" = "NOT_INSTALLED" ]; then
      if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}🆕${NC} $name — newly installed since snapshot"
      else
        echo -e "  ${YELLOW}⏭️${NC}  $name — still not installed"
      fi
      continue
    fi

    # Capture current state
    if capture_help "$name" "$cmd" "$subs" "$tmp_dir"; then
      # Compare main help
      local has_changes=false
      local change_details=""

      # Check version change
      local old_ver=$(cat "$snap_dir/${name}.version" 2>/dev/null | head -1)
      local new_ver=$(cat "$tmp_dir/${name}.version" 2>/dev/null | head -1)

      if [ "$old_ver" != "$new_ver" ]; then
        has_changes=true
        change_details="Version: $old_ver → $new_ver"
      fi

      # Check main help diff
      if ! diff -q "$snap_dir/${name}.help" "$tmp_dir/${name}.help" > /dev/null 2>&1; then
        has_changes=true

        # Count added/removed lines
        local added=$(diff "$snap_dir/${name}.help" "$tmp_dir/${name}.help" 2>/dev/null | grep -c "^>" || true)
        local removed=$(diff "$snap_dir/${name}.help" "$tmp_dir/${name}.help" 2>/dev/null | grep -c "^<" || true)
        change_details="${change_details:+$change_details | }Main help: +$added/-$removed lines"
      fi

      # Check subcommand help diffs
      IFS=',' read -ra SUBS <<< "$subs"
      local sub_changes=()
      for sub in "${SUBS[@]}"; do
        if [ -f "$snap_dir/${name}_${sub}.help" ] && [ -f "$tmp_dir/${name}_${sub}.help" ]; then
          if ! diff -q "$snap_dir/${name}_${sub}.help" "$tmp_dir/${name}_${sub}.help" > /dev/null 2>&1; then
            has_changes=true
            sub_changes+=("$sub")
          fi
        fi
      done

      if [ ${#sub_changes[@]} -gt 0 ]; then
        change_details="${change_details:+$change_details | }Changed subcommands: ${sub_changes[*]}"
      fi

      if $has_changes; then
        echo -e "  ${RED}🔄${NC} $name — CHANGED"
        echo -e "     ${YELLOW}$change_details${NC}"
        changed=$((changed + 1))
      else
        echo -e "  ${GREEN}✅${NC} $name — unchanged"
        unchanged=$((unchanged + 1))
      fi
    else
      echo -e "  ${RED}❌${NC} $name — was installed, now MISSING"
      new_missing=$((new_missing + 1))
    fi
  done

  rm -rf "$tmp_dir"

  echo ""
  echo "==========================================="
  echo "  STALENESS REPORT"
  echo "==========================================="
  echo -e "  ${GREEN}Unchanged:${NC} $unchanged"
  echo -e "  ${RED}Changed:${NC}   $changed"
  echo -e "  ${RED}Missing:${NC}   $new_missing"
  echo ""

  if [ "$changed" -eq 0 ] && [ "$new_missing" -eq 0 ]; then
    echo -e "  ${GREEN}All service CLIs match their snapshots. Skill references are current.${NC}"
    exit 0
  else
    echo -e "  ${YELLOW}⚠️  $changed CLI(s) have changed since the snapshot.${NC}"
    echo -e "  ${YELLOW}Review the service reference files for affected CLIs.${NC}"
    echo ""
    echo "  Next steps:"
    echo "    1. Check changelogs for the changed CLIs"
    echo "    2. Update the affected service reference files in references/services/"
    echo "    3. Run: $0 --snapshot   to update the baseline"
    exit 1
  fi
}

report() {
  local snap_dir="${SNAPSHOT_DIR}/current"

  if [ ! -d "$snap_dir" ]; then
    echo -e "${RED}No snapshot found. Run with --snapshot first.${NC}"
    exit 1
  fi

  echo -e "${CYAN}Generating detailed diff report...${NC}"
  echo ""

  local tmp_dir=$(mktemp -d)

  for entry in "${TRACKED_CLIS[@]}"; do
    IFS='|' read -r name cmd subs <<< "$entry"

    if [ "$(cat "$snap_dir/${name}.help" 2>/dev/null)" = "NOT_INSTALLED" ]; then
      continue
    fi

    if capture_help "$name" "$cmd" "$subs" "$tmp_dir"; then
      # Show full diff for main help
      if ! diff -q "$snap_dir/${name}.help" "$tmp_dir/${name}.help" > /dev/null 2>&1; then
        echo "================================================================"
        echo "  $name --help"
        echo "================================================================"
        diff --color=always "$snap_dir/${name}.help" "$tmp_dir/${name}.help" || true
        echo ""
      fi

      # Show full diff for each changed subcommand
      IFS=',' read -ra SUBS <<< "$subs"
      for sub in "${SUBS[@]}"; do
        if [ -f "$snap_dir/${name}_${sub}.help" ] && [ -f "$tmp_dir/${name}_${sub}.help" ]; then
          if ! diff -q "$snap_dir/${name}_${sub}.help" "$tmp_dir/${name}_${sub}.help" > /dev/null 2>&1; then
            echo "----------------------------------------------------------------"
            echo "  $name $sub --help"
            echo "----------------------------------------------------------------"
            diff --color=always "$snap_dir/${name}_${sub}.help" "$tmp_dir/${name}_${sub}.help" || true
            echo ""
          fi
        fi
      done
    fi
  done

  rm -rf "$tmp_dir"
}

# Route to the right mode
case "$MODE" in
  --snapshot|-s)
    snapshot
    ;;
  --compare|-c)
    compare
    ;;
  --report|-r)
    report
    ;;
  --help|-h)
    echo "Usage: $0 [--snapshot|--compare|--report]"
    echo ""
    echo "  --snapshot, -s   Create/update CLI help snapshots (baseline)"
    echo "  --compare, -c    Compare current CLIs against snapshots (default)"
    echo "  --report, -r     Generate detailed diff report for changed CLIs"
    echo ""
    echo "Tracked CLIs:"
    for entry in "${TRACKED_CLIS[@]}"; do
      IFS='|' read -r name cmd subs <<< "$entry"
      echo "  - $name ($cmd): subcommands: $subs"
    done
    ;;
  *)
    compare
    ;;
esac
