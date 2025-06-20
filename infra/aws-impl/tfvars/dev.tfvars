name        = "inferno"
environment = "dev"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:3a85fb439cbdf07a94de868ec16fa84a2f4982ca" # old working core image
imageUrl         = "ghcr.io/hl7au/au-fhir-inferno:6a4c3eda83198640a2311e87a774c858f1488dda-dev"       # use the image that is not tagged with -nginx
platformImageUri = "ghcr.io/hl7au/au-fhir-inferno:6a4c3eda83198640a2311e87a774c858f1488dda-nginx-dev" # use the image that IS tagged with -nginx
usesWrapper      = true
cluster_name     = "sparked-k8s"
vpc_name         = "sparked-k8s-vpc"
