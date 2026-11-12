#!/usr/bin/env bash
set -euo pipefail

#
# install-lb-controller.sh — Install/upgrade the AWS Load Balancer Controller (PETPLAT-29)
#
# Spec: docs/technical-spec.md#aws-load-balancer-controller, #irsa-roles
#
# Steps:
#   1. Read cluster name, VPC ID and IRSA role ARN from the env's Terraform outputs
#   2. Check kubectl points at that cluster
#   3. helm repo add eks https://aws.github.io/eks-charts
#   4. Apply the chart's CRDs (helm install/upgrade never upgrades CRDs itself)
#   5. helm upgrade --install into kube-system with service account
#      aws-load-balancer-controller annotated with petclinic-{env}-lb-controller-role
#   6. Wait for rollout and verify the "alb" IngressClass
#
# Usage:
#   ./scripts/install-lb-controller.sh dev
#   ./scripts/install-lb-controller.sh prod --replicas 2
#
# Requires: terraform (env already applied), aws CLI v2, kubectl, helm 3.
# Works on Linux, macOS and Git Bash on Windows.
#

CHART_VERSION="3.6.2" # app v3.6.2 — must match terraform/modules/eks var.lb_controller_version
REGION="ap-south-1"
NAMESPACE="kube-system"
RELEASE="aws-load-balancer-controller"
SERVICE_ACCOUNT="aws-load-balancer-controller"
REPLICAS=""

usage() {
  echo "Usage: $0 <dev|prod> [--replicas N] [--region REGION]"
  echo ""
  echo "  --replicas  Controller replicas (default: 1 for dev, 2 for prod)"
  echo "  --region    AWS region (default: ap-south-1)"
  exit "${1:-0}"
}

[[ $# -ge 1 ]] || usage 1
ENV="$1"
shift
case "$ENV" in
  dev | prod) ;;
  -h | --help) usage 0 ;;
  *)
    echo "ERROR: environment must be dev or prod (got '$ENV')" >&2
    usage 1
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --replicas)
      REPLICAS="${2:?--replicas needs a value}"
      shift 2
      ;;
    --region)
      REGION="${2:?--region needs a value}"
      shift 2
      ;;
    -h | --help) usage 0 ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      usage 1
      ;;
  esac
done

if [[ -z "$REPLICAS" ]]; then
  if [[ "$ENV" == "prod" ]]; then REPLICAS=2; else REPLICAS=1; fi
fi
[[ "$REPLICAS" =~ ^[1-9][0-9]*$ ]] || {
  echo "ERROR: --replicas must be a positive integer" >&2
  exit 1
}

for bin in terraform aws kubectl helm; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "ERROR: '$bin' not found in PATH" >&2
    exit 1
  }
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV"
VALUES_FILE="$REPO_ROOT/k8s/base/aws-load-balancer-controller/values.yaml"

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1" || true
}

echo "==> Reading Terraform outputs from terraform/environments/$ENV"
CLUSTER_NAME="$(tf_out eks_cluster_name)"
VPC_ID="$(tf_out vpc_id)"
ROLE_ARN="$(tf_out lb_controller_role_arn)"

for pair in "eks_cluster_name:$CLUSTER_NAME" "vpc_id:$VPC_ID" "lb_controller_role_arn:$ROLE_ARN"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: Terraform output '$name' is empty — apply terraform/environments/$ENV first." >&2
    exit 1
  fi
done

echo "    cluster : $CLUSTER_NAME"
echo "    vpc     : $VPC_ID"
echo "    role    : $ROLE_ARN"
echo "    replicas: $REPLICAS"

# Guard against installing into the wrong cluster.
echo "==> Checking kubectl context"
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$CURRENT_CONTEXT" != *"cluster/$CLUSTER_NAME" && "$CURRENT_CONTEXT" != "$CLUSTER_NAME" ]]; then
  echo "    Context is '$CURRENT_CONTEXT'; switching to $CLUSTER_NAME"
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null
fi
kubectl get --raw /readyz >/dev/null

echo "==> Adding Helm repo eks"
helm repo add eks https://aws.github.io/eks-charts --force-update >/dev/null
helm repo update eks >/dev/null

echo "==> Applying CRDs from chart $CHART_VERSION"
# Server-side apply: the CRDs are large, and this also upgrades them on re-runs.
helm show crds eks/aws-load-balancer-controller --version "$CHART_VERSION" |
  kubectl apply --server-side --force-conflicts -f -

echo "==> Installing $RELEASE (chart $CHART_VERSION) into $NAMESPACE"
helm upgrade --install "$RELEASE" eks/aws-load-balancer-controller \
  --namespace "$NAMESPACE" \
  --version "$CHART_VERSION" \
  --values "$VALUES_FILE" \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set replicaCount="$REPLICAS" \
  --set serviceAccount.create=true \
  --set serviceAccount.name="$SERVICE_ACCOUNT" \
  --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ROLE_ARN" \
  --wait \
  --timeout 5m

echo "==> Waiting for controller rollout"
kubectl -n "$NAMESPACE" rollout status deployment/"$RELEASE" --timeout=180s

echo "==> Verifying"
kubectl get ingressclass alb
kubectl -n "$NAMESPACE" get deployment "$RELEASE"
kubectl -n "$NAMESPACE" get serviceaccount "$SERVICE_ACCOUNT" \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'

echo ""
echo "Done. Next: deploy the Ingress (PETPLAT-30):"
echo "  ./scripts/render-ingress.sh $ENV | kubectl apply -f -"
