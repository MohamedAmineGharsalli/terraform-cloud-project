# ---------------------------------------------------------------------------
# dev environment - root module.
#
# Wires the six reusable modules together:
#   network -> security -> load-balancer -> compute
#                       \-> database
#                       \-> storage
#
# The compute module gets an explicit depends_on = [module.network] so the NAT
# route exists before the instances try to reach SSM and the package repos.
# ---------------------------------------------------------------------------

locals {
  environment = "dev"
  name_prefix = "${var.project_name}-${local.environment}"

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  })
}

module "network" {
  source = "../../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags
}

module "security" {
  source = "../../modules/security"

  name_prefix  = local.name_prefix
  vpc_id       = module.network.vpc_id
  enable_https = var.enable_https
  tags         = local.common_tags
}

module "load_balancer" {
  source = "../../modules/load-balancer"

  name_prefix           = local.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  enable_https          = var.enable_https
  certificate_arn       = var.enable_https ? var.certificate_arn : ""
  tags                  = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  name_prefix           = local.name_prefix
  project_name          = var.project_name
  app_subnet_ids        = module.network.app_subnet_ids
  app_security_group_id = module.security.app_security_group_id
  instance_profile_name = module.security.lab_instance_profile_name
  target_group_arn      = module.load_balancer.target_group_arn
  instance_type         = var.instance_type
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
  cpu_target_value      = var.cpu_target_value
  use_ssm_ami           = var.use_ssm_ami
  tags                  = local.common_tags

  depends_on = [module.network]
}

module "database" {
  source = "../../modules/database"

  name_prefix               = local.name_prefix
  db_subnet_ids             = module.network.db_subnet_ids
  db_security_group_id      = module.security.db_security_group_id
  db_name                   = var.db_name
  db_username               = var.db_username
  db_password               = var.db_password
  instance_class            = var.db_instance_class
  allocated_storage         = var.db_allocated_storage
  multi_az                  = var.db_multi_az
  backup_retention_period   = var.db_backup_retention
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_final_snapshot_identifier
  deletion_protection       = var.db_deletion_protection
  apply_immediately         = var.db_apply_immediately
  tags                      = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  name_prefix       = local.name_prefix
  bucket_name       = var.bucket_name
  aws_region        = var.aws_region
  enable_versioning = var.enable_versioning
  tags              = local.common_tags
}
