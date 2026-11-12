#!/usr/bin/env bash
set -euo pipefail

#
# ecr-login.sh — Authenticate Docker to the ECR private registry (PETPLAT-21)
#
# Runs, per docs/technical-spec.md#ecr-authentication:
#   aws ecr get-login-password --region <region> \
#     | docker login --username AWS --password-stdin {account}.dkr.ecr.<region>.amazonaws.com
#
# The account ID is resolved from the current AWS credentials (sts get-caller-identity).
# The token is valid for 12 hours. The password is piped via stdin and never
# echoed, stored in a variable, or passed on the command line.
#
# Usage:
#   ./scripts/ecr-login.sh                      # region ap-south-1
#   ./scripts/ecr-login.sh --region eu-west-1
#
# Works on Linux, macOS (bash 3.2+) and Git Bash on Windows.
# Requires: aws CLI v2, docker; credentials with ecr:GetAuthorizationToken + sts:GetCallerIdentity.
#

REGION="ap-south-1"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo ""
  echo "  --region   AWS region of the ECR registry (default: ap-south-1)"
  echo "  -h|--help  Show this help"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      [[ $# -ge 2 && -n "$2" ]] || { echo "Error: --region requires a value" >&2; usage 1; }
      REGION="$2"; shift 2 ;;
    --region=*)
      REGION="${1#*=}"; shift ;;
    -h|--help)
      usage 0 ;;
    *)
      echo "Error: unknown argument '$1'" >&2; usage 1 ;;
  esac
done

[[ "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || { echo "Error: invalid region '$REGION'" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI not found in PATH" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Error: docker not found in PATH" >&2; exit 1; }

echo "==> Resolving AWS account ID"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo "Error: could not determine AWS account ID (got '$ACCOUNT_ID')" >&2; exit 1; }

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> Logging in to ${REGISTRY}"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Docker is authenticated to ${REGISTRY} (token valid for 12 hours)"
