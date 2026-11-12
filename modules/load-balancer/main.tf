# ---------------------------------------------------------------------------
# Load balancer module: Application Load Balancer, target group and listeners.
#
#   Internet --80--> ALB --> target group --> app instances (port 80)
#
# HTTPS is optional (enable_https): when enabled, an HTTPS listener is created
# and the HTTP listener redirects to it (requires an ACM certificate + a domain).
# ---------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "this" {
  name     = "${var.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # Fast failover: a target is healthy after 2 successful checks and unhealthy
  # after 2 failures (interval 30s).
  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg" })
}

# HTTP listener: forwards to the target group, or redirects to HTTPS when enabled.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "forward"

    target_group_arn = var.enable_https ? null : aws_lb_target_group.this.arn

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []

      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-listener-http" })
}

# HTTPS listener (optional).
resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-listener-https" })

  lifecycle {
    precondition {
      condition     = length(var.certificate_arn) > 0
      error_message = "certificate_arn must be set when enable_https = true."
    }
  }
}
