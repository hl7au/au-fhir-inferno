name        = "inferno"
environment = "prod"
## MOVED TO apps/inferno-prod in aehrc/sparked-argo
# imageUrl         = MOVED TO deploy/prod-image.yaml
# platformImageUri = MOVED TO apps/inferno-prod in aehrc/sparked-argo
# validatorImageUri       = MOVED TO apps/inferno-prod in aehrc/sparked-argo
usesWrapper             = true
cluster_name            = "sparkey"
vpc_name                = "sparkey-vpc"
snapshot_identifier     = "prod-inferno-sparked-snapshot-manual"
postgres_instance_class = "db.t4g.medium"
rds_name                = "prod-inferno-postgresql"
deletion_protection     = true