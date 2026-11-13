# Kubernetes Overlays (PETPLAT-45, 46, 47)

Kustomize overlays that turn the environment-agnostic base in `k8s/base/` into
dev and prod deployments. They also serve as the requirements for the Helm values
files in E-16 (`helm-values/dev.yaml`, `helm-values/prod.yaml`); see
[technical-spec.md#kubernetes-overlays](../../docs/technical-spec.md#kubernetes-overlays).

## Usage

```bash
kubectl apply -f k8s/base/namespaces.yaml                       # once per cluster
./scripts/render-external-secrets.sh dev | kubectl apply -f -   # rds-credentials, openai-api-key
./scripts/render-overlay.sh dev | kubectl apply -f -            # all 8 services
```

`render-overlay.sh` runs `kubectl kustomize` and fills `${ECR_REGISTRY}` and
`${RDS_ENDPOINT}` from Terraform outputs. Validate offline with:

```bash
kubectl kustomize k8s/overlays/dev | kubectl apply --dry-run=client -f -
```

## Settings

| Setting | Dev | Prod |
|---|---|---|
| Namespace | `petclinic-dev` | `petclinic-prod` |
| Replicas | 1 for every service | config 2, discovery 2, gateway 2, customers 2, visits 2, vets 2, genai 1, admin 1 |
| HPA (CPU 70%) | none | gateway 2–6; customers, visits, vets 2–4; genai 1–3 |
| CPU request | 50m (all services) | base: 100m (gateway 200m) |
| CPU limit | base: 500m (gateway 1000m) | base: 500m (gateway 1000m) |
| Memory | 128Mi request / 512Mi limit | 128Mi request / 512Mi limit |
| Pod spreading | none | `topologySpreadConstraints` across nodes (ScheduleAnyway) |
| Image | `${ECR_REGISTRY}/petclinic-dev/{service}:{sha}` | `${ECR_REGISTRY}/petclinic-prod/{service}:{sha}` |
| Extra label | `environment: dev` | `environment: prod` |

Prod resources: prod keeps the full base requests that dev reduces. Memory stays
at 512Mi, the image's memory limit (CLAUDE.md), and the prod pods' requests have
to fit on 2x t4g.small (2 GiB each). The prod overlay scales with more pods
(HPA), not with bigger ones.

Image tags are 7-character app-repo commit SHAs (`e8b747a` = the initial
PETPLAT-85 push). To change a tag:
`cd k8s/overlays/dev && kustomize edit set image 'ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/petclinic-ENV/api-gateway=${ECR_REGISTRY}/petclinic-dev/api-gateway:<sha>'`
(single quotes keep the `${ECR_REGISTRY}` placeholder literal; needs the standalone `kustomize` binary).

HPA and replicas: in prod the HPA owns the replica count once it is running. The
`replicas:` values only set the initial size. Re-applying the overlay resets the
count until the HPA scales it again.

## Translation into Helm values (E-16)

| Overlay setting | `helm-values/dev.yaml` | `helm-values/prod.yaml` |
|---|---|---|
| replicas | `replicaCount: 1` | `replicaCount: 2` (genai/admin override to 1 in their service file or a per-service prod block) |
| HPA | `autoscaling.enabled: false` | `autoscaling: {enabled: true, minReplicas, maxReplicas, targetCPUUtilizationPercentage: 70}`; gateway max 6, genai min 1 / max 3 |
| CPU request | `resources.requests.cpu: 50m` | chart default (service file sets gateway 200m/1000m) |
| Spreading | — | `topologySpreadConstraints` value |
| Image | `image.repository` per service; `image.tag: <sha>` written by CI | same, prod registry path |
| Namespace | ArgoCD `destination.namespace: petclinic-dev` | `petclinic-prod` |
