# Petclinic Platform Runbook

**Last Updated:** 2026-11-09

**Purpose:** Step-by-step procedures for day-to-day operation of the Petclinic platform on AWS (EKS, Terraform). Each procedure applies to either environment; replace `{env}` with `dev` or `prod`.

## Table of Contents

- [Procedure: Configure kubectl for an EKS cluster](#procedure-configure-kubectl-for-an-eks-cluster)
- [Procedure: Grant cluster access to additional IAM users/roles](#procedure-grant-cluster-access-to-additional-iam-usersroles)
- [Procedure: Upgrade EKS add-on versions](#procedure-upgrade-eks-add-on-versions)

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
