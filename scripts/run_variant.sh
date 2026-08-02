#!/usr/bin/env bash
#one variant, full lifecycle, timestamped
set -euo pipefail
export TZ=UTC+1

VARIANT="$1"
RUN="${2:-1}"
STATE_RG="rg-tfstate"
STATE_SA="sttfstatembf"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a
source <(sed 's/\r$//' "$ROOT/.env")
set +a


cd "$ROOT/variants/$VARIANT"

terraform init -reconfigure \
    -backend-config="resource_group_name=$STATE_RG" \
    -backend-config="storage_account_name=$STATE_SA" \
    -backend-config="container_name=tfstate" \
    -backend-config="key=${VARIANT}.terraform.tfstate" \

terraform validate
terraform plan -out tfplan
terraform show -no-color tfplan > "$ROOT/results/plans/${VARIANT}_run${RUN}.txt"

terraform apply -auto-approve tfplan | tee "$ROOT/results/logs/${VARIANT}_run${RUN}.log"
DEPLOY_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "${VARIANT},${RUN},${DEPLOY_TS}" >> "$ROOT/results/run_log.csv"
echo "APPLY COMPLETE  ${VARIANT} run ${RUN} at ${DEPLOY_TS}"
