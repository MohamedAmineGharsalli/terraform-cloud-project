# ---------------------------------------------------------------------------
# Compute module: Amazon Linux 2023 AMI, launch template and Auto Scaling Group.
#
# Instances run in the private app subnets, are reachable only through the ALB
# (security group reference), require IMDSv2 and use an encrypted gp3 volume.
# Admin access is done through SSM Session Manager (LabInstanceProfile): there
# is no SSH.
#
# AMI resolution:
#   - default: public SSM parameter (al2023-ami-kernel-default-x86_64)
#   - fallback: aws_ami data source (set use_ssm_ami = false) if the SCP blocks
#     SSM parameter reads.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023" {
  count = var.use_ssm_ami ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ami" "al2023" {
  count = var.use_ssm_ami ? 0 : 1

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  ami_id = var.use_ssm_ami ? data.aws_ssm_parameter.al2023[0].value : data.aws_ami.al2023[0].id
}

# ---------------------------------------------------------------------------
# Launch template
# ---------------------------------------------------------------------------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = local.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.app_security_group_id]

  # IMDSv2 required: the user_data must request a token to read metadata.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/../../scripts/user_data.sh", {
    project_name = var.project_name
  }))

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name_prefix}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name_prefix}-app-volume" })
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-lt" })
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
#
# The environment adds an explicit depends_on (module.network) so the NAT route
# exists before instances try to reach SSM / the package repositories.
# ---------------------------------------------------------------------------
resource "aws_autoscaling_group" "this" {
  name                      = "${var.name_prefix}-asg"
  vpc_zone_identifier       = var.app_subnet_ids
  desired_capacity          = var.desired_capacity
  min_size                  = var.min_size
  max_size                  = var.max_size
  health_check_type         = "ELB"
  health_check_grace_period = 60
  target_group_arns         = [var.target_group_arn]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.name_prefix}-app" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    precondition {
      condition     = var.max_size >= var.min_size
      error_message = "max_size must be greater than or equal to min_size."
    }

    precondition {
      condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
      error_message = "desired_capacity must be between min_size and max_size."
    }
  }
}

# ---------------------------------------------------------------------------
# Target-tracking scaling policy: keep average CPU at 50 %
# ---------------------------------------------------------------------------
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name_prefix}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_value
  }
}
