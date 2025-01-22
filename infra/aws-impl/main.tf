locals {
  env_name  = "${var.environment}-${var.name}"
  manifests = fileset(path.module, "manifests/*.yaml")

  rds_name = "${local.env_name}-postgresql"
  region   = "ap-southeast-2"

  tags = {
    Name       = local.env_name
    GithubRepo = "https://github.com/hl7au/au-fhir-inferno"
  }
}

## Inferno Application
resource "helm_release" "inferno" {
  name             = local.env_name
  chart            = "../helm/inferno"
  namespace        = local.env_name
  create_namespace = true
  reset_values     = true

  values = [
    file("../helm/inferno/values.yaml"),
  ]

  set_sensitive {
    name  = "postgresql.global.postgresql.auth.username"
    value = jsondecode(data.aws_secretsmanager_secret_version.rds.secret_string)["username"]
  }
  set_sensitive {
    name  = "postgresql.global.postgresql.auth.password"
    value = jsondecode(data.aws_secretsmanager_secret_version.rds.secret_string)["password"]
  }

  set_sensitive {
    name  = "postgresql.externaldbhost"
    value = split(":", module.rds.db_instance_endpoint)[0] # rds module provides endpoint with the port but inferno expects only the hostname
  }
  set {
    name  = "ingress.hostnames[0]"
    value = "${var.environment}.inferno.sparked-fhir.com"
  }

  # External domain: if prod => "inferno.hl7.org.au"
  set {
    name  = "ingress.hostnames[1]"
    value = var.environment == "prod" ? "inferno.hl7.org.au" : "inferno.${var.environment}.hl7.org.au"
  }

  set {
    name  = "inferno.imageUrl"
    value = var.imageUrl
  }

  set {
    name  = "nginx.platformImageUri"
    value = var.platformImageUri
  }

  set {
    name  = "inferno.validatorImageUri"
    value = var.validatorImageUri
  }

  set {
    name  = "nginx.example"
    value = "1234"
  }

  set {
    name  = "inferno.usesWrapper"
    value = var.usesWrapper
  }

  depends_on = [
    module.rds,
  ]
}



################################################################################
# RDS Module
################################################################################
module "rds" {
  source = "terraform-aws-modules/rds/aws"

  identifier = local.rds_name

  create_db_option_group    = false
  create_db_parameter_group = false

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.postgres_instance_class

  allocated_storage = 20

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = "inferno"
  username = "postgres"
  port     = 5432

  db_subnet_group_name   = data.aws_db_subnet_group.k8s.name
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  # backup_window           = "03:00-06:00"
  # backup_retention_period = 1

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags                        = local.tags
  manage_master_user_password = true


  snapshot_identifier = var.snapshot_identifier
}

################################################################################
# Supporting Resources
################################################################################


module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.rds_name}-security-group"
  description = "Inferno PostgreSQL security group"
  vpc_id      = data.aws_vpc.k8s.id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "Inferno PostgreSQL access from within VPC"
      cidr_blocks = data.aws_vpc.k8s.cidr_block
    },
  ]

  tags = local.tags
}