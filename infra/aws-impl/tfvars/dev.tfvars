name        = "sparkey-inferno"
environment = "dev"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:3a85fb439cbdf07a94de868ec16fa84a2f4982ca" # old working core image
imageUrl         = "ghcr.io/hl7au/au-fhir-inferno:7a78c7ce86294055090ae7379ba3eefd1f6f128f-dev"       # use the image that is not tagged with -nginx
platformImageUri = "ghcr.io/hl7au/au-fhir-inferno:7a78c7ce86294055090ae7379ba3eefd1f6f128f-nginx-dev" # use the image that IS tagged with -nginx
usesWrapper      = true
cluster_name     = "sparkey"
vpc_name         = "sparkey-vpc"
