name        = "inferno"
environment = "prod"
## MOVED TO infra/helm/inferno/values-prod.yaml
# imageUrl         = MOVED TO infra/helm/inferno/values-prod.yaml
# platformImageUri = MOVED TO infra/helm/inferno/values-prod.yaml
# validatorImageUri       = MOVED TO infra/helm/inferno/values-prod.yaml
usesWrapper             = true
cluster_name            = "sparkey"
vpc_name                = "sparkey-vpc"
snapshot_identifier     = "prod-inferno-sparked-snapshot-manual"
postgres_instance_class = "db.t4g.medium"
rds_name                = "prod-inferno-postgresql"