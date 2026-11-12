# ---------------------------------------------------------------------------
# Security module
#
# Three chained security groups (defence in depth, referenced by SG id, never
# by CIDR):
#
#   Internet --80/443--> [alb-sg] --80--> [app-sg] --3306--> [db-sg]
#
# It also exposes the pre-existing IAM resources of the AWS Academy Learner Lab
# (LabRole / LabInstanceProfile) through data sources, because creating IAM
# roles, policies or instance profiles is FORBIDDEN in the lab.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Pre-existing Learner Lab IAM resources (read-only)
# ---------------------------------------------------------------------------
data "aws_iam_role" "lab_role" {
  name = var.lab_role_name
}

data "aws_iam_instance_profile" "lab_instance_profile" {
  name = var.lab_instance_profile_name
}

# ---------------------------------------------------------------------------
# 1. ALB security group: HTTP (and optional HTTPS) from the Internet
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Application Load Balancer: HTTP/HTTPS from the Internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from the Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []

    content {
      description = "HTTPS from the Internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })
}

# ---------------------------------------------------------------------------
# 2. App security group: HTTP only from the ALB security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "Application instances: HTTP only from the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from the ALB security group only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-sg" })
}

# ---------------------------------------------------------------------------
# 3. DB security group: MySQL only from the app security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "RDS database: MySQL only from the application instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from the app security group only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-sg" })
}
