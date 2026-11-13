#!/usr/bin/env bash
set -euo pipefail

#
# install-external-secrets.sh — Install/upgrade External Secrets Operator (PETPLAT-34)
#
# Spec: docs/technical-spec.md#external-secrets-operator-eso, #irsa-roles
#
# Steps:
#   1. Read cluster name and the ESO IRSA role ARN from the env's Terraform outputs
#   2. Check kubectl points at that cluster
#   3. Apply the external-secrets namespace
#   4. Render the ESO chart (CRDs + controller, webhook, cert-controller) with
#      `helm template` and install it with `kubectl apply --server-side`
#      (technical-spec.md: "Installation: kubectl apply (CRDs + controller)").
#      Service account external-secrets-sa is annotated with petclinic-{env}-eso-role.
#   5. Wait for the CRDs and deployments, then apply the ClusterSecretStore
#   6. Smoke test (in petclinic-{env}): a throwaway ExternalSecret reads the username of
#      petclinic/{env}/rds-credentials, the K8s Secret is checked, then removed
#
# Usage:
#   ./scripts/install-external-secrets.sh dev
#   ./scripts/install-external-secrets.sh prod --skip-smoke-test
#
# Requires: terraform (env already applied), aws CLI v2, kubectl, helm 3
# (helm is used only to render manifests; nothing is installed as a Helm release).
# Works on Linux, macOS and Git Bash on Windows.
#
# Upgrades: bump CHART_VERSION and re-run. Server-side apply updates objects in
# place; objects a newer chart no longer renders are not pruned automatically.
#

CHART_VERSION="2.15.0" # app v2.15.0
CHART_REPO="https://charts.external-secrets.io"
REGION="ap-south-1"
NAMESPACE="external-secrets"
RELEASE="external-secrets"
SERVICE_ACCOUNT="external-secrets-sa"
STORE_NAME="aws-secrets-manager"
SMOKE_TEST=true

usage() {
  echo "Usage: $0 <dev|prod> [--skip-smoke-test] [--region REGION]"
  echo ""
  echo "  --skip-smoke-test  Do not run the sample ExternalSecret check"
  echo "  --region           AWS region (default: ap-south-1)"
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
    --skip-smoke-test)
      SMOKE_TEST=false
      shift
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

for bin in terraform aws kubectl helm; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "ERROR: '$bin' not found in PATH" >&2
    exit 1
  }
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/$ENV"
ESO_DIR="$REPO_ROOT/k8s/base/external-secrets"

VALUES_ARGS=(--values "$ESO_DIR/values.yaml")
if [[ "$ENV" == "prod" ]]; then
  VALUES_ARGS+=(--values "$ESO_DIR/values-prod.yaml")
fi

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1" || true
}

echo "==> Reading Terraform outputs from terraform/environments/$ENV"
CLUSTER_NAME="$(tf_out eks_cluster_name)"
ROLE_ARN="$(tf_out eso_role_arn)"

for pair in "eks_cluster_name:$CLUSTER_NAME" "eso_role_arn:$ROLE_ARN"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "ERROR: Terraform output '$name' is empty — apply terraform/environments/$ENV first." >&2
    exit 1
  fi
done

echo "    cluster : $CLUSTER_NAME"
echo "    role    : $ROLE_ARN"
echo "    chart   : external-secrets $CHART_VERSION"

# Guard against installing into the wrong cluster.
echo "==> Checking kubectl context"
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$CURRENT_CONTEXT" != *"cluster/$CLUSTER_NAME" && "$CURRENT_CONTEXT" != "$CLUSTER_NAME" ]]; then
  echo "    Context is '$CURRENT_CONTEXT'; switching to $CLUSTER_NAME"
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" >/dev/null
fi
kubectl get --raw /readyz >/dev/null

echo "==> Applying namespace $NAMESPACE"
kubectl apply -f "$ESO_DIR/namespace.yaml"

echo "==> Rendering chart $CHART_VERSION and applying CRDs + controller"
# Server-side apply: the CRDs are large, and re-runs upgrade them in place.
# Fields filled at runtime by cert-controller (webhook caBundle, TLS secret data)
# are not in the rendered manifest, so SSA never overwrites them.
helm template "$RELEASE" external-secrets \
  --repo "$CHART_REPO" \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" \
  --skip-tests \
  "${VALUES_ARGS[@]}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name="$SERVICE_ACCOUNT" \
  --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ROLE_ARN" |
  kubectl apply --server-side --force-conflicts --field-manager=install-external-secrets -f -

echo "==> Waiting for CRDs"
kubectl wait --for condition=established --timeout=120s \
  crd/externalsecrets.external-secrets.io \
  crd/clustersecretstores.external-secrets.io

echo "==> Waiting for deployments"
for deploy in "$RELEASE" "$RELEASE-webhook" "$RELEASE-cert-controller"; do
  kubectl -n "$NAMESPACE" rollout status deployment/"$deploy" --timeout=300s
done

echo "==> Applying ClusterSecretStore $STORE_NAME"
# The validating webhook needs its certificate from cert-controller; retry briefly.
for attempt in 1 2 3 4 5 6; do
  if kubectl apply -f "$ESO_DIR/cluster-secret-store.yaml"; then
    break
  fi
  [[ $attempt -lt 6 ]] || {
    echo "ERROR: could not apply the ClusterSecretStore" >&2
    exit 1
  }
  echo "    webhook not ready yet, retrying in 10s ($attempt/6)"
  sleep 10
done
kubectl wait --for=condition=Ready --timeout=120s clustersecretstore/"$STORE_NAME"

if [[ "$SMOKE_TEST" == "true" ]]; then
  # The ClusterSecretStore only serves the app namespaces, so the test runs in
  # petclinic-{env}. Create it if PETPLAT-38 has not applied namespaces.yaml yet.
  APP_NAMESPACE="petclinic-$ENV"
  echo "==> Smoke test in $APP_NAMESPACE: sync petclinic/$ENV/rds-credentials (username only)"
  if ! kubectl get namespace "$APP_NAMESPACE" >/dev/null 2>&1; then
    echo "    Namespace $APP_NAMESPACE not found; creating it"
    kubectl create namespace "$APP_NAMESPACE"
  fi
  SMOKE="eso-smoke-test"
  cleanup_smoke() {
    # Deleting the ExternalSecret garbage-collects the Secret it owns.
    kubectl -n "$APP_NAMESPACE" delete externalsecret "$SMOKE" --ignore-not-found >/dev/null
  }
  trap cleanup_smoke EXIT

  kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: $SMOKE
  namespace: $APP_NAMESPACE
  labels:
    app.kubernetes.io/name: $SMOKE
    app.kubernetes.io/part-of: petclinic
    app.kubernetes.io/component: infrastructure
    app.kubernetes.io/managed-by: kubectl
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: $STORE_NAME
    kind: ClusterSecretStore
  target:
    name: $SMOKE
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: petclinic/$ENV/rds-credentials
        property: username
EOF
  kubectl -n "$APP_NAMESPACE" wait --for=condition=Ready --timeout=120s externalsecret/"$SMOKE"
  # Check the key name only; never print values.
  if kubectl -n "$APP_NAMESPACE" get secret "$SMOKE" -o jsonpath='{.data.username}' | grep -q .; then
    echo "    OK: K8s Secret $SMOKE created with key 'username'"
  else
    echo "ERROR: smoke-test Secret $SMOKE has no 'username' key" >&2
    exit 1
  fi
  cleanup_smoke
  trap - EXIT
fi

echo "==> Verifying"
kubectl -n "$NAMESPACE" get deployments
kubectl get clustersecretstore "$STORE_NAME"
kubectl -n "$NAMESPACE" get serviceaccount "$SERVICE_ACCOUNT" \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'

echo ""
echo "Done. Next: sync the application secrets into petclinic-$ENV (PETPLAT-35/36):"
echo "  kubectl create namespace petclinic-$ENV --dry-run=client -o yaml | kubectl apply -f -   # if not created by the smoke test / PETPLAT-38"
echo "  ./scripts/render-external-secrets.sh $ENV | kubectl apply -f -"
