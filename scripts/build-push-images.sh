#!/usr/bin/env bash
set -euo pipefail

#
# build-push-images.sh — Build linux/arm64 images for all 8 services and push to ECR (PETPLAT-85)
#
# 1. Maven builds the Spring Boot JARs only (no -P buildDocker profile):
#      ./mvnw clean install -DskipTests
# 2. For each service, docker buildx builds a linux/arm64 image (Graviton t4g
#    nodes) from the application repo's shared docker/Dockerfile, with the
#    correct runtime port from docs/technical-spec.md#service-inventory (the
#    pom.xml docker.image.exposed.port values are wrong for several services),
#    and pushes it straight to:
#      {account}.dkr.ecr.{region}.amazonaws.com/petclinic-{env}/{service}:{tag}
#
# The application repo is READ-ONLY: this script only reads it and writes to
# its Maven target/ directories. Each image's build context is a temp dir that
# holds just the service JAR.
#
# Usage:
#   ./scripts/build-push-images.sh                                  # dev, tag v1.0.0, all services
#   ./scripts/build-push-images.sh --tag "$(git -C ../spring-petclinic-microservices rev-parse --short=7 HEAD)"
#   ./scripts/build-push-images.sh --services api-gateway,vets-service --skip-maven
#   ./scripts/build-push-images.sh --no-push                        # build + load locally only
#
# Requires: aws CLI v2, docker with buildx, JDK 17 (for ./mvnw).
# On x86 hosts, arm64 emulation (QEMU binfmt) must be installed:
#   docker run --privileged --rm tonistiigi/binfmt --install arm64
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT="petclinic"
ENVIRONMENT="dev"
REGION="ap-south-1"
TAG="v1.0.0"
PLATFORM="linux/arm64"
APP_REPO="${REPO_ROOT}/../spring-petclinic-microservices"
SKIP_MAVEN=false
PUSH=true

ALL_SERVICES="config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server"
SERVICES="$ALL_SERVICES"

# Runtime ports from technical-spec.md#service-inventory (bash 3.2 safe: no associative arrays).
service_port() {
  case "$1" in
    config-server)     echo 8888 ;;
    discovery-server)  echo 8761 ;;
    api-gateway)       echo 8080 ;;
    customers-service) echo 8081 ;;
    visits-service)    echo 8082 ;;
    vets-service)      echo 8083 ;;
    genai-service)     echo 8084 ;;
    admin-server)      echo 9090 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<EOF
Usage: $0 [options]

  --env <dev|prod>        Target environment / ECR namespace petclinic-{env}/ (default: dev)
  --tag <tag>             Image tag (default: v1.0.0). 'latest' is rejected.
  --region <aws-region>   ECR region (default: ap-south-1)
  --app-repo <path>       Path to spring-petclinic-microservices (default: ../spring-petclinic-microservices)
  --services <a,b,...>    Comma-separated subset of services (default: all 8)
  --skip-maven            Reuse JARs already in each module's target/ directory
  --no-push               Build and load into the local Docker engine instead of pushing
  -h|--help               Show this help

Services: ${ALL_SERVICES}
EOF
  exit "${1:-0}"
}

need_value() { [[ $# -ge 2 && -n "$2" ]] || { echo "Error: $1 requires a value" >&2; usage 1; }; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)        need_value "$@"; ENVIRONMENT="$2"; shift 2 ;;
    --env=*)      ENVIRONMENT="${1#*=}"; shift ;;
    --tag)        need_value "$@"; TAG="$2"; shift 2 ;;
    --tag=*)      TAG="${1#*=}"; shift ;;
    --region)     need_value "$@"; REGION="$2"; shift 2 ;;
    --region=*)   REGION="${1#*=}"; shift ;;
    --app-repo)   need_value "$@"; APP_REPO="$2"; shift 2 ;;
    --app-repo=*) APP_REPO="${1#*=}"; shift ;;
    --services)   need_value "$@"; SERVICES="${2//,/ }"; shift 2 ;;
    --services=*) SERVICES="${1#*=}"; SERVICES="${SERVICES//,/ }"; shift ;;
    --skip-maven) SKIP_MAVEN=true; shift ;;
    --no-push)    PUSH=false; shift ;;
    -h|--help)    usage 0 ;;
    *)            echo "Error: unknown argument '$1'" >&2; usage 1 ;;
  esac
done

################################################################################
# Validate inputs and tools
################################################################################

[[ "$ENVIRONMENT" == "dev" || "$ENVIRONMENT" == "prod" ]] || { echo "Error: --env must be dev or prod" >&2; exit 1; }
[[ "$REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || { echo "Error: invalid region '$REGION'" >&2; exit 1; }
[[ "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || { echo "Error: invalid image tag '$TAG'" >&2; exit 1; }
[[ "$TAG" != "latest" ]] || { echo "Error: the 'latest' tag is not allowed (use a version or commit SHA)" >&2; exit 1; }

for svc in $SERVICES; do
  service_port "$svc" >/dev/null || { echo "Error: unknown service '$svc'. Valid: ${ALL_SERVICES}" >&2; exit 1; }
done

[[ -f "${APP_REPO}/pom.xml" && -f "${APP_REPO}/docker/Dockerfile" ]] \
  || { echo "Error: ${APP_REPO} is not the spring-petclinic-microservices repo (pom.xml or docker/Dockerfile missing)" >&2; exit 1; }
APP_REPO="$(cd "$APP_REPO" && pwd)"
DOCKERFILE="${APP_REPO}/docker/Dockerfile"

command -v docker >/dev/null 2>&1 || { echo "Error: docker not found in PATH" >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "Error: docker buildx is not available" >&2; exit 1; }
if [[ "$PUSH" == true ]]; then
  command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI not found in PATH" >&2; exit 1; }
fi

echo "==> Checking that the buildx builder supports ${PLATFORM}"
if ! docker buildx inspect --bootstrap 2>/dev/null | grep -i 'platforms:' | grep -q "${PLATFORM}"; then
  echo "Error: the current buildx builder cannot build ${PLATFORM}." >&2
  echo "       Install arm64 emulation: docker run --privileged --rm tonistiigi/binfmt --install arm64" >&2
  exit 1
fi

APP_REVISION="$(git -C "$APP_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"

################################################################################
# ECR registry + repository checks
################################################################################

if [[ "$PUSH" == true ]]; then
  echo "==> Resolving AWS account ID"
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  [[ "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo "Error: could not determine AWS account ID" >&2; exit 1; }
  REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

  echo "==> Checking ECR repositories exist and tag '${TAG}' is unused (prod repos are IMMUTABLE)"
  for svc in $SERVICES; do
    repo="${PROJECT}-${ENVIRONMENT}/${svc}"
    aws ecr describe-repositories --region "$REGION" --repository-names "$repo" >/dev/null 2>&1 \
      || { echo "Error: ECR repository ${repo} not found in ${REGION}. Apply terraform/environments/${ENVIRONMENT} first." >&2; exit 1; }
    mutability="$(aws ecr describe-repositories --region "$REGION" --repository-names "$repo" \
      --query 'repositories[0].imageTagMutability' --output text)"
    if [[ "$mutability" == "IMMUTABLE" ]] \
      && aws ecr describe-images --region "$REGION" --repository-name "$repo" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
      echo "Error: ${repo}:${TAG} already exists and the repository is IMMUTABLE. Use a new tag." >&2
      exit 1
    fi
  done

  "${SCRIPT_DIR}/ecr-login.sh" --region "$REGION"
else
  REGISTRY="local"
fi

################################################################################
# Maven: build JARs only (no buildDocker profile)
################################################################################

if [[ "$SKIP_MAVEN" == false ]]; then
  MODULES=""
  for svc in $SERVICES; do MODULES="${MODULES:+${MODULES},}spring-petclinic-${svc}"; done
  echo "==> Building JARs with Maven (${MODULES})"
  (cd "$APP_REPO" && ./mvnw -B clean install -DskipTests -pl "$MODULES" -am)
fi

################################################################################
# docker buildx: one linux/arm64 image per service
################################################################################

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/petclinic-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

BUILT=""
for svc in $SERVICES; do
  module="spring-petclinic-${svc}"
  port="$(service_port "$svc")"

  # Exactly one executable JAR: skip *-sources/*-javadoc/*-plain and .jar.original.
  jar=""
  count=0
  for f in "${APP_REPO}/${module}/target/${module}-"*.jar; do
    [[ -f "$f" ]] || continue
    case "$f" in *-sources.jar|*-javadoc.jar|*-plain.jar|*-tests.jar) continue ;; esac
    jar="$f"; count=$((count + 1))
  done
  [[ "$count" -eq 1 ]] || { echo "Error: expected 1 JAR in ${module}/target, found ${count}. Run without --skip-maven." >&2; exit 1; }

  artifact="$(basename "$jar" .jar)"
  context="${STAGING}/${svc}"
  mkdir -p "$context"
  cp "$jar" "${context}/${artifact}.jar"

  image="${REGISTRY}/${PROJECT}-${ENVIRONMENT}/${svc}:${TAG}"
  if [[ "$PUSH" == true ]]; then output="--push"; else output="--load"; fi

  echo "==> Building ${image} (${PLATFORM}, port ${port}, ${artifact}.jar)"
  docker buildx build \
    --platform "$PLATFORM" \
    --file "$DOCKERFILE" \
    --build-arg "ARTIFACT_NAME=${artifact}" \
    --build-arg "EXPOSED_PORT=${port}" \
    --label "org.opencontainers.image.title=${svc}" \
    --label "org.opencontainers.image.revision=${APP_REVISION}" \
    --label "org.opencontainers.image.version=${TAG}" \
    --provenance=false \
    --sbom=false \
    --tag "$image" \
    "$output" \
    "$context"

  BUILT="${BUILT}  ${image}"$'\n'
done

echo ""
if [[ "$PUSH" == true ]]; then
  echo "==> Pushed images:"
  printf '%s' "$BUILT"
  echo ""
  echo "Verify: aws ecr describe-images --region ${REGION} --repository-name ${PROJECT}-${ENVIRONMENT}/<service> --image-ids imageTag=${TAG}"
else
  echo "==> Built images (loaded locally, not pushed):"
  printf '%s' "$BUILT"
fi
