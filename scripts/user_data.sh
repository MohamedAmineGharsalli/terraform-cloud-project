#!/bin/bash
# ---------------------------------------------------------------------------
# user_data - Amazon Linux 2023 application instance
#
# Installs nginx and serves a small page showing the hostname, the instance id
# and the AZ. The instance id is read from the instance metadata through
# IMDSv2 (a token is mandatory because http_tokens = "required").
# Refreshing the ALB URL therefore shows load balancing across instances.
#
# NOTE (Terraform templatefile): ${project_name} is a Terraform interpolation.
# Shell variables are written without braces ($TOKEN, $INSTANCE_ID, ...) so that
# Terraform does not try to interpolate them.
# ---------------------------------------------------------------------------
set -euo pipefail

dnf update -y || true
dnf install -y nginx

# --- IMDSv2: obtain a token, then read the metadata -------------------------
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")

INSTANCE_ID=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

# --- Demo web page ----------------------------------------------------------
cat > /usr/share/nginx/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Terraform Cloud Project</title>
  <style>
    body { font-family: sans-serif; margin: 3rem; }
    h1 { color: #2c3e50; }
    code { background: #f4f4f4; padding: 0.1rem 0.3rem; }
  </style>
</head>
<body>
  <h1>Terraform Cloud Project</h1>
  <p>Project: ${project_name}</p>
  <p>Hostname: <code>$(hostname)</code></p>
  <p>Instance ID: <code>$INSTANCE_ID</code></p>
  <p>Availability Zone: <code>$AZ</code></p>
</body>
</html>
HTML

systemctl enable --now nginx
