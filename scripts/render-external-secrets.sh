#!/usr/bin/env bash
set -euo pipefail

#
# render-external-secrets.sh — Render the application ExternalSecrets for an
# environment (PETPLAT-35, PETPLAT-36)
#
# Fills ${ENVIRONMENT} / ${NAMESPACE} in k8s/base/external-secrets/{rds-credentials,openai-api-key}.yaml
# and prints the manifests to stdout. It never applies anything itself.
# No secret values are involved: the manifests only reference Secrets Manager keys.
#
# Usage:
#   ./scripts/render-external-secrets.sh dev                      # print
#   ./scripts/render-external-secrets.sh dev | kubectl apply -f - # apply
#
# Requires: envsubst (gettext).
#

usage() {
  echo "Usage: $0 <dev|prod>"
  exit "${1:-0}"
}

[[ $# -eq 1 ]] || usage 1
ENV="$1"
case "$ENV" in
  dev | prod) ;;
  -h | --help) usage 0 ;;
  *)
    echo "ERROR: environment must be dev or prod (got '$ENV')" >&2
    usage 1
    ;;
esac

command -v envsubst >/dev/null 2>&1 || {
  echo "ERROR: 'envsubst' not found in PATH" >&2
  exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESO_DIR="$REPO_ROOT/k8s/base/external-secrets"

export ENVIRONMENT="$ENV"
export NAMESPACE="petclinic-$ENV"

first=true
for manifest in rds-credentials.yaml openai-api-key.yaml; do
  [[ "$first" == "true" ]] || echo "---"
  first=false
  # Restrict substitution to the known placeholders.
  envsubst '${ENVIRONMENT} ${NAMESPACE}' <"$ESO_DIR/$manifest"
done
