# Petclinic Platform Runbook

**Last Updated:** 2026-11-12

**Purpose:** Step-by-step procedures for day-to-day operation of the Petclinic platform on AWS (EKS, Terraform). Each procedure applies to either environment; replace `{env}` with `dev` or `prod`.

## Table of Contents

- [Procedure: Configure kubectl for an EKS cluster](#procedure-configure-kubectl-for-an-eks-cluster)
- [Procedure: Grant cluster access to additional IAM users/roles](#procedure-grant-cluster-access-to-additional-iam-usersroles)
- [Procedure: Upgrade EKS add-on versions](#procedure-upgrade-eks-add-on-versions)
- [Procedure: Log in to ECR](#procedure-log-in-to-ecr)
- [Procedure: Build and push service images to ECR](#procedure-build-and-push-service-images-to-ecr)
- [Procedure: Expose the app over HTTPS (DNS, LB controller, Ingress)](#procedure-expose-the-app-over-https-dns-lb-controller-ingress)

---

## EKS

### Procedure: Configure kubectl for an EKS cluster

**When:** First access to a cluster, or after the cluster was recreated.
**Who:** An IAM user/role that has an EKS access entry on the cluster (see next procedure).
**Time:** 2 minutes

**Steps:**
1. Print the exact command from Terraform state:
   ```bash
   cd terraform/environments/{env} && terraform output -raw kubeconfig_command
   ```
2. Run it (equivalent form):
   ```bash
   aws eks update-kubeconfig --name petclinic-{env} --region ap-south-1
   ```

> **IMDS is blocked for pods.** Nodes enforce IMDSv2 with hop limit 1 (`node_imds_hop_limit`), so pods that are not `hostNetwork` cannot read instance metadata or use the node role. Every pod that calls AWS must use an IRSA role. Helm charts that auto-detect region or VPC from IMDS need them set explicitly. For example, the AWS Load Balancer Controller needs `--set region=ap-south-1 --set vpcId=$(terraform output -raw vpc_id)`.

**Verify:**
- `kubectl get nodes` lists 2 nodes in `Ready` state.
- `kubectl get pods -n kube-system` shows `coredns`, `kube-proxy`, `aws-node` and `ebs-csi-*` pods `Running`.

**Rollback:**
- Remove the context: `kubectl config delete-context arn:aws:eks:ap-south-1:{account}:cluster/petclinic-{env}`

---

### Procedure: Grant cluster access to additional IAM users/roles

**When:** A new engineer or automation role needs `kubectl` access.
**Who:** Engineer with Terraform apply rights for the environment.
**Time:** 10 minutes

Access uses EKS access entries (authentication mode `API_AND_CONFIG_MAP`), managed in `terraform/modules/eks/access.tf`. The IAM principal that runs Terraform gets cluster-admin automatically, unless it is the account root user (root is never granted access). Every other principal is listed in `eks_cluster_admin_principal_arns`.

**Steps:**
1. Get the IAM ARN of the user or role. For a role, use the role ARN (`arn:aws:iam::{account}:role/{name}`), not the assumed-role session ARN:
   ```bash
   aws iam get-role --role-name {role-name} --query Role.Arn --output text
   ```
2. Add it to `terraform/environments/{env}/terraform.tfvars`:
   ```hcl
   eks_cluster_admin_principal_arns = [
     "arn:aws:iam::{account}:role/{role-name}",
   ]
   ```
3. Plan and apply:
   ```bash
   cd terraform/environments/{env} && terraform plan -out plan.out
   ```
   ```bash
   cd terraform/environments/{env} && terraform apply plan.out
   ```
4. The new principal runs the [Configure kubectl](#procedure-configure-kubectl-for-an-eks-cluster) procedure.

**Verify:**
- `aws eks list-access-entries --cluster-name petclinic-{env} --region ap-south-1` lists the ARN.
- The new principal can run `kubectl get nodes`.

**Rollback:**
- Remove the ARN from `eks_cluster_admin_principal_arns`, then plan and apply again.

> Access is cluster-admin only today. For narrower access, add an `aws_eks_access_policy_association` with `AmazonEKSViewPolicy` or `AmazonEKSEditPolicy` and `access_scope { type = "namespace" }` in `terraform/modules/eks/access.tf`.

---

### Procedure: Upgrade EKS add-on versions

**When:** A new add-on build is released, or before/after a Kubernetes version upgrade.
**Who:** Engineer with Terraform apply rights for the environment.
**Time:** 20 minutes per environment

Add-on versions are pinned in `addon_versions` (`terraform/modules/eks/variables.tf`). Upgrade dev first, then prod.

**Steps:**
1. List versions compatible with the cluster version (repeat for `vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver`):
   ```bash
   aws eks describe-addon-versions --region ap-south-1 --kubernetes-version 1.35 --addon-name coredns --query 'addons[0].addonVersions[].addonVersion' --output text
   ```
2. Check the installed versions:
   ```bash
   aws eks list-addons --cluster-name petclinic-{env} --region ap-south-1
   ```
   ```bash
   aws eks describe-addon --cluster-name petclinic-{env} --region ap-south-1 --addon-name coredns --query addon.addonVersion --output text
   ```
3. Update the pinned version in `addon_versions` in `terraform/modules/eks/variables.tf`. Upgrade `vpc-cni` one minor version at a time.
4. Plan and check that only `aws_eks_addon` resources change in place:
   ```bash
   cd terraform/environments/{env} && terraform plan -out plan.out
   ```
5. Apply:
   ```bash
   cd terraform/environments/{env} && terraform apply plan.out
   ```

**Verify:**
- `aws eks describe-addon --cluster-name petclinic-{env} --region ap-south-1 --addon-name {addon} --query addon.status --output text` returns `ACTIVE`.
- `kubectl get pods -n kube-system` shows all add-on pods `Running`.

**Rollback:**
- Set the previous version in `addon_versions`, then plan and apply again. EKS supports downgrading an add-on to an earlier version that is compatible with the cluster.

> Conflict resolution is `OVERWRITE`: manual changes to add-on settings made with `kubectl` are replaced on the next apply. Put add-on settings in Terraform.

---

## ECR

### Procedure: Log in to ECR

**When:** Before any manual `docker push`/`docker pull` against `petclinic-{env}/*` repositories. The token lasts 12 hours.
**Who:** IAM principal with `ecr:GetAuthorizationToken` and `sts:GetCallerIdentity`.
**Time:** 1 minute

**Steps:**
1. Run the helper (defaults to `ap-south-1`):
   ```bash
   ./scripts/ecr-login.sh
   ```
2. Equivalent manual command:
   ```bash
   aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-south-1.amazonaws.com"
   ```

**Verify:**
- Output ends with `Login Succeeded`.

**Rollback:**
- `docker logout {account}.dkr.ecr.ap-south-1.amazonaws.com`

---

### Procedure: Build and push service images to ECR

**When:** First-time image push (PETPLAT-85) before the first Helm/ArgoCD deploy, or a manual rebuild outside CI. CI handles all later builds.
**Who:** IAM principal with ECR push rights on `petclinic-{env}/*`; Docker with buildx; JDK 17.
**Time:** 15–30 minutes (arm64 emulation on x86 is slow)

Maven builds only the JARs. `docker buildx` builds `linux/arm64` images for the Graviton nodes from the app repo's `docker/Dockerfile`, using the runtime ports from the technical spec. The `-P buildDocker` Maven profile is not used.

**Steps:**
1. Apply the environment so the 8 repositories exist:
   ```bash
   cd terraform/environments/{env} && terraform plan -out plan.out && terraform apply plan.out
   ```
2. On an x86 host, install arm64 emulation (one time; Apple Silicon skips this):
   ```bash
   docker run --privileged --rm tonistiigi/binfmt --install arm64
   ```
3. Clone the app repo next to this repo (`../spring-petclinic-microservices`), then build and push all 8 images with the initial tag:
   ```bash
   ./scripts/build-push-images.sh --env {env} --tag v1.0.0
   ```
   The script runs these commands for each service:
   ```bash
   ./mvnw -B clean install -DskipTests
   docker buildx build --platform linux/arm64 --file docker/Dockerfile --build-arg ARTIFACT_NAME=spring-petclinic-{service}-{version} --build-arg EXPOSED_PORT={port} --provenance=false --sbom=false --tag {account}.dkr.ecr.ap-south-1.amazonaws.com/petclinic-{env}/{service}:v1.0.0 --push {dir-containing-jar}
   ```
4. To tag with the app commit SHA instead:
   ```bash
   ./scripts/build-push-images.sh --env {env} --tag "$(git -C ../spring-petclinic-microservices rev-parse --short=7 HEAD)"
   ```

**Verify:**
- Each repository has the tag:
  ```bash
  for s in config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server; do aws ecr describe-images --region ap-south-1 --repository-name petclinic-{env}/$s --image-ids imageTag=v1.0.0 --query 'imageDetails[0].imageTags' --output text; done
  ```
- The image is arm64:
  ```bash
  docker buildx imagetools inspect {account}.dkr.ecr.ap-south-1.amazonaws.com/petclinic-{env}/api-gateway:v1.0.0
  ```
- Scan results: `aws ecr describe-image-scan-findings --region ap-south-1 --repository-name petclinic-{env}/api-gateway --image-id imageTag=v1.0.0`

**Rollback:**
- Dev (MUTABLE): rebuild and push the same tag again.
- Prod (IMMUTABLE): tags cannot be overwritten. Push a new tag and point the Helm values at it.
- Rollback window: the lifecycle policy keeps only the last 10 tagged images per repository. A rollback (ArgoCD or Helm) to an older tag fails with `ImagePullBackOff`. Check that the tag still exists before rolling back: `aws ecr describe-images --region ap-south-1 --repository-name petclinic-{env}/{service} --image-ids imageTag={tag}`
- Remove a bad image: `aws ecr batch-delete-image --region ap-south-1 --repository-name petclinic-{env}/{service} --image-ids imageTag={tag}`

---

## DNS & Ingress

### Procedure: Expose the app over HTTPS (DNS, LB controller, Ingress)

**When:** First-time setup of `petclinic-dev.{domain}` (PETPLAT-28 to PETPLAT-32), or after re-creating the cluster.
**Who:** Platform engineer with Terraform apply rights and cluster-admin access.
**Time:** 30-60 min (mostly NS propagation and ACM validation).

**Steps:**
1. Set `domain_name` in `terraform/environments/dev/terraform.tfvars`. If the zone does not exist yet, also set `wait_for_certificate_validation = false`.
2. Plan and apply the zone, certificate and LB controller IRSA role:
   ```bash
   cd terraform/environments/dev
   terraform plan -out plan.out
   terraform apply plan.out
   terraform output dns_zone_name_servers
   ```
3. At your domain registrar, set the domain's NS records to the four name servers from step 2. Check delegation: `nslookup -type=NS {domain} 8.8.8.8`
4. Set `wait_for_certificate_validation = true`, then plan and apply again. The apply completes once ACM has issued `*.{domain}`.
5. Install the AWS Load Balancer Controller (chart 3.6.2, IRSA role `petclinic-dev-lb-controller-role`):
   ```bash
   ./scripts/install-lb-controller.sh dev
   ```
6. Deploy the Ingress. It needs the `api-gateway` Service on port 8080 in `petclinic-dev`.
   ```bash
   ./scripts/render-ingress.sh dev | kubectl apply -f -
   kubectl -n petclinic-dev get ingress api-gateway -w   # wait for ADDRESS
   ```
7. Create the alias record `petclinic-dev.{domain}` pointing to `petclinic-dev-alb`: set `create_alb_dns_record = true` in `terraform.tfvars`, then plan and apply.

**Verify:**
- `kubectl -n kube-system get deploy aws-load-balancer-controller` shows all replicas ready.
- `kubectl get ingressclass alb` exists.
- `aws elbv2 describe-load-balancers --names petclinic-dev-alb --region ap-south-1 --query 'LoadBalancers[0].State.Code'` returns `active`.
- `curl -sI http://petclinic-dev.{domain}` returns `301` with `Location: https://...`.
- `curl -s https://petclinic-dev.{domain}/actuator/health` returns `{"status":"UP"...}`.

**Rollback:**
- Remove the record: set `create_alb_dns_record = false`, then plan and apply.
- Remove the ALB: `kubectl -n petclinic-dev delete ingress api-gateway`. The controller deletes the ALB and its target groups.
- Uninstall the controller only after all Ingresses are gone: `helm uninstall aws-load-balancer-controller -n kube-system`.
- The hosted zone has `prevent_destroy`. Prod reuses it and the registrar points at its name servers, so do not delete it.
