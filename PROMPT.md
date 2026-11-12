Read Epic E-1 Foundation and Remote State from docs/jira-backlog.md. Implement all 5 stories - PetclinicPlatform1 through PetclinicPlatform5. 
For each story, read the acceptance criteria and the Technical Spec references in docs/technical-spec.md. 
Start with PetclinicPlatform1 directory structure, then PetclinicPlatform2 bootstrap script, then PetclinicPlatform3 and PetclinicPlatform4 backends, then PetclinicPlatform5 providers and versions.


## Prompt-1
Read the following stories from docs/jira-backlog.md:
- PetclinicPlatform6: Create VPC module
- PetclinicPlatform8: Create baseline security groups
- PetclinicPlatform9: Wire VPC module into dev
- PetclinicPlatform10: Wire VPC module into prod
Read the technical spec at docs/technical-spec.md, specifically:
- VPC Network Design section
- Security Groups section
- Terraform Modules section

Build everything these stories require. Follow the acceptance criteria exactly.
After you are done, run terraform validate in both dev and prod.
Then use the terraform-reviewer agent to review the module and the security-auditor agent for security and best practices.
Fix any issues the reviewers find, then validate again.
Print the summary in short.


## Prompt-2
Read the following stories from docs/jira-backlog.md:
- PetclinicPlatform12: Create EKS module cluster and IAM roles
- PetclinicPlatform13: Add managed node group
- PetclinicPlatform14: Create kubectl access configuration
- PetclinicPlatform15: Wire EKS module into dev
- PetclinicPlatform16: Deploy and verify dev EKS cluster
- PetclinicPlatform17: Wire EKS module into prod
- PetclinicPlatform84: Manage EKS add-ons via Terraform
Read the technical spec at docs/technical-spec.md, specifically:
- EKS Cluster section
- IRSA Roles section
Build everything these stories require. Follow the acceptance criteria exactly.
After you are done, run terraform validate in both dev and prod.
Then use the terraform-reviewer agent to review the module for security and best practices.
Fix any issues the reviewer finds, then validate again.


## Prompt-3
Read the following stories from docs/jira-backlog.md:
- PetclinicPlatform18: Create ECR module
- PetclinicPlatform19: Add lifecycle policy and tag immutability configuration
- PetclinicPlatform20: Wire ECR module into dev environment and deploy
- PetclinicPlatform21: Create ECR login helper script
- PetclinicPlatform85: Build and push Docker images to ECR (initial)
Read the technical spec at docs/technical-spec.md, specifically:
- ECR Container Registry section
- Docker Build section
- Terraform Modules section (ECR module)

Build everything these stories require. Follow the acceptance criteria exactly.
The build-push script must use docker buildx with --platform linux/arm64 for Graviton nodes. Do not rely on Maven's buildDocker profile for image creation - use Maven to build the JARs, then docker buildx to build ARM64 images.
After you are done, run terraform validate in both dev and prod.
Then use the terraform-reviewer agent to review the module for security and best practices.
Fix any issues the reviewer finds, then validate again.


## Prompt-4
Read the following stories from docs/jira-backlog.md:
- PetclinicPlatform22: Create RDS module
- PetclinicPlatform23: Create database credentials in Secrets Manager
- PetclinicPlatform24: Create database initialization strategy
- PetclinicPlatform25: Wire RDS module into dev environment
- PetclinicPlatform26: Deploy and verify dev RDS
- PetclinicPlatform27: Wire RDS module into prod environment
Read the technical spec at docs/technical-spec.md, specifically:
- RDS Database section
- Secrets Management section
- Security Groups section (RDS security group)
- Terraform Modules section (RDS module)

Build everything these stories require. Follow the acceptance criteria exactly.
After you are done, run terraform validate in both dev and prod.
Then use the terraform-reviewer agent to review the module for security and best practices.
Fix any issues the reviewer finds, then validate again.


## Prompt-5
Read the following stories from docs/jira-backlog.md:
- PetclinicPlatform28: Create DNS module - Route 53 hosted zone
- PetclinicPlatform29: Install AWS Load Balancer Controller on EKS
- PetclinicPlatform30: Create Ingress manifest for API Gateway
- PetclinicPlatform31: Create DNS record pointing to ALB
- PetclinicPlatform32: Wire DNS module into dev environment
Read the technical spec at docs/technical-spec.md, specifically:
- DNS and Ingress section
- Security Groups section (ALB security group)
- IRSA Roles section (LB controller role)
- Terraform Modules section (DNS module)

Build everything these stories require. Follow the acceptance criteria exactly.
This section produces both Terraform resources AND Kubernetes resources - make sure you generate both.
The AWS Load Balancer Controller should be installed via Helm chart (aws-load-balancer-controller from eks.amazonaws.com/charts). Generate a shell script at scripts/install-lb-controller.sh that handles the CRDs, Helm repo add, and helm install with the correct service account and IRSA role ARN. Make sure the script is executable (chmod +x).
After you are done, run terraform validate in both dev and prod.
Then use the terraform-reviewer agent to review the Terraform module for security and best practices.
Then use the k8s-validator agent to validate the Kubernetes manifests against project standards.
Fix any issues either reviewer finds, then validate again.
