# ---------------------------------------------------------------------------
# Database module: private MySQL RDS instance.
#
# The instance lives in the private database subnets (no route to the
# Internet) and is reachable ONLY from the application security group
# (TCP 3306). It is encrypted at rest and never publicly accessible.
#
# Credentials: the master password is never stored in code. It is supplied
# through the TF_VAR_db_password environment variable (or the DB_PASSWORD
# GitHub secret) and marked sensitive.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db-subnet-group"
  description = "Private subnets used by the ${var.name_prefix} database"
  subnet_ids  = var.db_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-subnet-group" })
}

resource "aws_db_instance" "this" {
  identifier = "${var.name_prefix}-db"

  # --- Engine --------------------------------------------------------------
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  # --- Storage -------------------------------------------------------------
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true

  # --- Network -------------------------------------------------------------
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  # --- Database and credentials -------------------------------------------
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # --- Backups / maintenance ----------------------------------------------
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  # --- Lifecycle -----------------------------------------------------------
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  deletion_protection       = var.deletion_protection
  apply_immediately         = var.apply_immediately

  # Minor upgrades are applied automatically during the maintenance window.
  auto_minor_version_upgrade = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-db" })

  lifecycle {
    precondition {
      condition     = var.skip_final_snapshot || length(var.final_snapshot_identifier) > 0
      error_message = "final_snapshot_identifier must be set when skip_final_snapshot = false."
    }

    precondition {
      condition     = var.max_allocated_storage == 0 || var.max_allocated_storage >= var.allocated_storage
      error_message = "max_allocated_storage must be 0 (disabled) or greater than or equal to allocated_storage."
    }
  }
}
