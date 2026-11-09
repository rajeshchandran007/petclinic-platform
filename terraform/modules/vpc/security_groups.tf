# Baseline security groups (PETPLAT-8). See docs/technical-spec.md#security-groups.
#
# Security groups are the primary access control boundary in the all-public design.
# Rules are standalone aws_vpc_security_group_{ingress,egress}_rule resources so each
# rule is individually tracked and the SGs can reference each other without cycles.

################################################################################
# Security groups
################################################################################

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane: API server access from worker nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker nodes: control plane, inter-node and ALB traffic"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL: port 3306 from EKS worker nodes only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Public ALB: HTTP/HTTPS from the internet, forwards to EKS nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

################################################################################
# EKS cluster SG rules
################################################################################

resource "aws_vpc_security_group_ingress_rule" "cluster_https_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "API server access from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-cluster-https-from-nodes" })
}

resource "aws_vpc_security_group_egress_rule" "cluster_all_out" {
  #checkov:skip=CKV_AWS_382:All-public design (ADR-0001); egress to AWS APIs/ECR/S3 via IGW is required
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Control plane outbound (kubelet, webhooks, AWS APIs)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.tags, { Name = "${local.name_prefix}-cluster-all-out" })
}

################################################################################
# EKS node SG rules
################################################################################

resource "aws_vpc_security_group_ingress_rule" "node_all_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All traffic from EKS control plane"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_cluster.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-node-all-from-cluster" })
}

resource "aws_vpc_security_group_ingress_rule" "node_all_from_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node communication (pod-to-pod, CoreDNS)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-node-all-from-self" })
}

resource "aws_vpc_security_group_ingress_rule" "node_kubelet_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Kubelet API from EKS control plane"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.eks_cluster.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-node-kubelet-from-cluster" })
}

resource "aws_vpc_security_group_ingress_rule" "node_nodeport_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "NodePort services from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  referenced_security_group_id = aws_security_group.alb.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-node-nodeport-from-alb" })
}

# Counterpart of the ALB "health checks to nodes" egress rule on 8080. With the AWS
# Load Balancer Controller in IP target mode the ALB targets pod IPs (which carry the
# node SG via the VPC CNI) on the container port, so the node SG must accept it.
resource "aws_vpc_security_group_ingress_rule" "node_app_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "ALB traffic and health checks to pods on 8080 (IP target mode)"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-node-app-from-alb" })
}

resource "aws_vpc_security_group_egress_rule" "node_all_out" {
  #checkov:skip=CKV_AWS_382:All-public design (ADR-0001); egress to AWS APIs/ECR/S3 via IGW is required
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound (ECR, S3, Secrets Manager, EKS API via IGW)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.tags, { Name = "${local.name_prefix}-node-all-out" })
}

################################################################################
# RDS SG rules — 3306 from EKS node SG ONLY. Never 0.0.0.0/0. No egress rules.
################################################################################

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EKS worker nodes only"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-rds-mysql-from-nodes" })
}

################################################################################
# ALB SG rules — the only SG with 0.0.0.0/0 ingress, and only on 80/443
################################################################################

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:Public-facing ALB; port 80 only redirects to 443
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet (redirected to HTTPS at the ALB)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-http" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-https" })
}

resource "aws_vpc_security_group_egress_rule" "alb_nodeport_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to NodePort targets on EKS nodes"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-nodeport-to-nodes" })
}

resource "aws_vpc_security_group_egress_rule" "alb_app_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Health checks and IP-mode targets on 8080"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.eks_node.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-app-to-nodes" })
}
