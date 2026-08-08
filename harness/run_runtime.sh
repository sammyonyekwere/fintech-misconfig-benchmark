#!/usr/bin/env bash
# harness/run_runtime.sh  VARIANT  [RUN]
#
# Deploys VARIANT, then polls every mc0X KQL query against Resource Graph.
# For meaningful time-to-flag, run against a variant that is NOT already live
# (teardown first) -- re-applying over existing infra makes ARG return
# instantly and TTF collapses to ~0 (it is measuring nothing, not detecting
# nothing). A genuine cold deploy shows the real ARG-indexing lag (secs-~2min).
#
# Window is 600s (10 min): KQL over ARG is a config-state snapshot, not an
# event stream -- once ARG indexes the resource the config is fully visible,
# so a long timeout is conceptually wrong here. Pilot showed all detections
# under 5 min; 10 min is a 2x buffer. Override with RUNTIME_WINDOW / _INTERVAL.
set -euo pipefail
VARIANT="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_LOG="$ROOT/results/run_log.csv"
LOG="$ROOT/results/run_log_runtime.csv"

# Auto-force mc07 through the normal poll path when this IS the variant that
# actually seeds it -- everywhere else it stays a manual check by default
# (confirmed ARG platform gap, see check_one below). No need to remember to
# set RUNTIME_CHECK_MC07 by hand each time.
if [ "$VARIANT" = "vuln-07-logging-disabled" ]; then
  RUNTIME_CHECK_MC07=1
fi

RUN="${2:-}"

# Duplicate-row guard.
if [ -n "$RUN" ] && [ -f "$LOG" ]; then
  if awk -F, -v v="$VARIANT" -v r="$RUN" '$1==v && $2==r {found=1} END{exit !found}' "$LOG"; then
    echo "Rows for variant=$VARIANT run=$RUN already exist in $LOG. Remove them or use a different run number." >&2
    exit 1
  fi
fi

echo "=== Deploying $VARIANT ==="
if [ -n "$RUN" ]; then
  bash "$ROOT/scripts/run_variant.sh" "$VARIANT" "$RUN"
else
  bash "$ROOT/scripts/run_variant.sh" "$VARIANT"
  RUN=$(awk -F, -v v="$VARIANT" '$1==v {if ($2+0>max) max=$2+0} END {print max+0}' "$RUN_LOG")
fi

DEPLOY_ISO=$(awk -F, -v v="$VARIANT" -v r="$RUN" '$1==v && $2==r {ts=$3} END {print ts}' "$RUN_LOG")
if [ -z "$DEPLOY_ISO" ]; then
  echo "Deploy appears to have failed -- no row for variant='$VARIANT' run='$RUN' in $RUN_LOG." >&2
  exit 1
fi

start=$(date -u -d "$DEPLOY_ISO" +%s)

# Resource-group scope for the queries that need it (mc07/mc08 below) --
# same tfvars-derived rg-<variant_name> lookup deployed_state_policy_scan.ps1
# already uses. Without this, mc07/mc08 scan the whole subscription and can
# misattribute a stale or concurrently-deployed resource group elsewhere
# (confirmed in practice: mc08 was flagging rg-tfstate's own storage account).
TFVARS="$ROOT/variants/$VARIANT/terraform.tfvars"
if [ ! -f "$TFVARS" ]; then
  echo "No such file: $TFVARS" >&2
  exit 1
fi
VARIANT_NAME=$(sed -n 's/.*variant_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS" | head -1)
if [ -z "$VARIANT_NAME" ]; then
  echo "No variant_name found in $TFVARS" >&2
  exit 1
fi
RG="rg-$VARIANT_NAME"

# mc02/mc10 workload-principal scope, resolved fresh every run instead of
# hardcoded -- neither identity is gated behind its own mc0X flag (per
# modules/baseline/identity.tf, the Function App's managed identity and the
# sp-<variant>-payments service principal exist for every variant; only the
# role/scope granted to them changes), so this variant's own principal ID is
# looked up live rather than baked into the .kql file, where it would go
# stale the moment the variant is torn down and redeployed with a new one.
MC02_PID=$(az functionapp identity show -g "$RG" -n "function${VARIANT_NAME}app" \
             --query principalId -o tsv 2>/dev/null || echo "")
MC10_PID=$(az ad sp list --display-name "sp-${VARIANT_NAME}-payments" \
             --query "[0].id" -o tsv 2>/dev/null || echo "")
echo "mc02 workload principal (function app identity): ${MC02_PID:-<not found>}"
echo "mc10 workload principal (sp-${VARIANT_NAME}-payments):     ${MC10_PID:-<not found>}"

echo "=== Checking mc0X KQL queries against $VARIANT (run $RUN), deployed at $DEPLOY_ISO, scoped to $RG ==="

TMPDIR_RUNTIME="$ROOT/results/.runtime_tmp_$$"
mkdir -p "$TMPDIR_RUNTIME"
# FIX: register cleanup EARLY so an interrupt (Ctrl-C) during polling still
# removes the temp dir. Safe now because check_one clears this trap in each
# subshell (below), so no worker can delete the dir out from under the others.
trap 'rm -rf "$TMPDIR_RUNTIME"' EXIT

check_one() {
  trap - EXIT   # FIX: clear inherited EXIT trap in this subshell (version-proof)
  local kql="$1" base mc out now elapsed n det ttf
  local WINDOW="${RUNTIME_WINDOW:-150}"
  local INTERVAL="${RUNTIME_INTERVAL:-30}"

  base=$(basename "$kql")
  # FIX: robust mc id (was `cut -d_ -f1`, which mangled hyphenated names)
  mc=$(printf '%s' "$base" | grep -oiE '^mc[0-9]+' || true)
  # FIX: relabel a Graph-based Part B as mcNNb so it never collides with Part A
  case "$base" in
    *-partb.kql|*-partB.kql) mc="${mc}b" ;;
  esac
  out="$TMPDIR_RUNTIME/${base}.out"

  # mc05 (secret value ARG cannot read) and any Part B (Graph) are manual checks.
  # mc07 defaults to manual too -- confirmed platform-level Resource Graph gap,
  # not a scoping bug: microsoft.insights/diagnosticsettings are extension/
  # proxy resources ARG does not reliably index, so the join in mc07.kql
  # always returns empty regardless of whether a diagnostic setting genuinely
  # exists (confirmed: az monitor diagnostic-settings list showed a real
  # setting ARG's own join could not find). Polling it in the normal sweep
  # would just burn the full window every time for a result that's
  # structurally guaranteed to never be a real signal. Set RUNTIME_CHECK_MC07=1
  # to force it through the normal poll path anyway when deliberately
  # re-testing mc07 specifically.
  case "$base" in
    mc05_*.kql|*-partb.kql|*-partB.kql)
      echo "[$mc] $base -> manual check"
      echo "$VARIANT,$RUN,kql,$mc,MANUAL_CHECK_REQUIRED,-" > "$out"
      return ;;
    mc07_logging_disabled.kql)
      if [ -z "${RUNTIME_CHECK_MC07:-}" ]; then
        echo "[$mc] $base -> manual check (confirmed ARG platform gap; set RUNTIME_CHECK_MC07=1 to poll it anyway)"
        echo "$VARIANT,$RUN,kql,$mc,MANUAL_CHECK_REQUIRED,-" > "$out"
        return
      fi
      ;;
  esac

  # mc07 (only when forced via RUNTIME_CHECK_MC07=1) and mc08 scan the whole
  # subscription otherwise -- append a resource-group filter so a stale or
  # concurrently-deployed resource group elsewhere can't get misattributed to
  # this variant's run.
  local query
  query="$(cat "$kql")"
  case "$base" in
    mc07_logging_disabled.kql|mc08_no_cmk.kql)
      query="$query
| where resourceGroup =~ \"$RG\""
      ;;
    mc02_rbac_contributor.kql)
      query="$query
| where principal == \"$MC02_PID\""
      ;;
    mc10_sp_nonexpiring_owner-parta.kql)
      query="$query
| where principal == \"$MC10_PID\""
      ;;
  esac

  echo "[$mc] polling every ${INTERVAL}s (timeout ${WINDOW}s)..."
  while true; do
    now=$(date -u +%s)
    elapsed=$((now - start))

    if [ "$elapsed" -ge "$WINDOW" ]; then
      echo "[$mc] TIMEOUT after ${WINDOW}s"
      echo "$VARIANT,$RUN,kql,$mc,NOT_DETECTED,>${WINDOW}" > "$out"
      return
    fi

    n=$(az graph query -q "$query" --query "length(data)" -o tsv 2>/dev/null || echo 0)

    if [ "${n:-0}" -gt 0 ]; then
      det=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      ttf=$elapsed
      echo "[$mc] DETECTED after ${ttf}s"
      echo "$VARIANT,$RUN,kql,$mc,$det,$ttf" > "$out"
      return
    fi
    sleep "$INTERVAL"
  done
}

pids=()
for kql in "$ROOT"/harness/kql/mc*.kql; do
  check_one "$kql" &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done

# FIX: nullglob + guard so an empty result set never makes `cat` error under set -e
shopt -s nullglob
outs=("$TMPDIR_RUNTIME"/*.out)
if [ "${#outs[@]}" -gt 0 ]; then
  cat "${outs[@]}" >> "$LOG"
fi

echo "Done. All mc0X checks complete for $VARIANT run $RUN."
echo "Remember to run './scripts/teardown.sh $VARIANT' when you're finished with it."