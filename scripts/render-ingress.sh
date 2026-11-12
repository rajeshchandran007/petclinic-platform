#!/usr/bin/env bash
set -euo pipefail

#
# render-ingress.sh — Render k8s/base/ingress/ingress.yaml for an environment (PETPLAT-30)
#
# Fills the template placeholders from Terraform outputs and prints the manifest
# to stdout. It never applies anything itself.
#
# Usage:
#   ./scripts/render-ingress.sh dev                      # print
#   ./scripts/render-ingress.sh dev | kubectl apply -f - # apply
#
# Requires: terraform (env already applied), envsubst (gettext).
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

for bin in terraform envsubst; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "ERROR: '$bin' not found in PATH" >&2
    exit 1
  }
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV"
TEMPLATE="$REPO_ROOT/k8s/base/ingress/ingress.yaml"

tf_out() {
  local value
  value="$(terraform -chdir="$TF_DIR" output -raw "$1" || true)"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: Terraform output '$1' is empty in terraform/environments/$ENV" >&2
    exit 1
  fi
  printf '%s' "$value"
}

export ENVIRONMENT="$ENV"
export NAMESPACE="petclinic-$ENV"
ACM_CERTIFICATE_ARN="$(tf_out acm_certificate_arn)"
ALB_SECURITY_GROUP_ID="$(tf_out alb_sg_id)"
export ACM_CERTIFICATE_ARN ALB_SECURITY_GROUP_ID

# Restrict substitution to the known placeholders.
envsubst '${ENVIRONMENT} ${NAMESPACE} ${ACM_CERTIFICATE_ARN} ${ALB_SECURITY_GROUP_ID}' <"$TEMPLATE"
