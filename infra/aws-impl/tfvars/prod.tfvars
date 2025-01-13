name        = "inferno"
environment = "prod"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:bb8de66a310a6dcb800b71e9da83a2a6221346c3" # old working core image
imageUrl            = "ghcr.io/hl7au/au-fhir-inferno:6d2b38572e76b791822f41fde596fbd199cbc182" # use the image that is not tagged with -nginx
platformImageUri    = "ghcr.io/hl7au/au-fhir-inferno:6d2b38572e76b791822f41fde596fbd199cbc182-nginx" # use the image that IS tagged with -nginx
usesWrapper         = true
cluster_name        = "sparked-k8s"
vpc_name            = "sparked-k8s-vpc"
snapshot_identifier = "final-prod-inferno-postgresql-c46a1109"
postgres_instance_class = "db.t4g.medium"
