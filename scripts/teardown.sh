
#!/usr/bin/env bash
# scripts/teardown.sh  —  destroy one variant, or all of them
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a
source <(sed 's/\r$//' "$ROOT/.env")
set +a
 

for V in "${@:-$(ls "$ROOT/variants")}"; do
  echo "== destroying $V"
  ( cd "$ROOT/variants/$V" && terraform destroy -auto-approve )
done
