#!/usr/bin/env bash
set -euo pipefail

#
# render-overlay.sh — Render k8s/overlays/{env} for an environment (PETPLAT-45/46)
#
# Builds the Kustomize overlay and fills the two template placeholders from
# Terraform outputs, printing the manifests to stdout. It never applies anything.
#
#   ${ECR_REGISTRY}  terraform output -raw ecr_registry_url
#   ${RDS_ENDPOINT}  terraform output -raw rds_endpoint
#
# Usage:
#   ./scripts/render-overlay.sh dev                      # print
#   ./scripts/render-overlay.sh dev | kubectl apply -f - # apply
#
# Prerequisites in the cluster: k8s/base/namespaces.yaml, and the ESO-synced
# Secrets rds-credentials / openai-api-key (./scripts/render-external-secrets.sh).
#
# Requires: terraform (env already applied), kubectl (>= 1.27, built-in kustomize),
#           envsubst (gettext).
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

for bin in terraform kubectl envsubst; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "ERROR: '$bin' not found in PATH" >&2
    exit 1
  }
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV"
OVERLAY="$REPO_ROOT/k8s/overlays/$ENV"

tf_out() {
  local value
  value="$(terraform -chdir="$TF_DIR" output -raw "$1" || true)"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: Terraform output '$1' is empty in terraform/environments/$ENV" >&2
    exit 1
  fi
  printf '%s' "$value"
}

ECR_REGISTRY="$(tf_out ecr_registry_url)"
RDS_ENDPOINT="$(tf_out rds_endpoint)"
export ECR_REGISTRY RDS_ENDPOINT

# Restrict substitution to the known placeholders.
kubectl kustomize "$OVERLAY" | envsubst '${ECR_REGISTRY} ${RDS_ENDPOINT}'
