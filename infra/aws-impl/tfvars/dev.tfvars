name        = "inferno"
environment = "dev"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:3a85fb439cbdf07a94de868ec16fa84a2f4982ca" # old working core image
imageUrl         = "ghcr.io/hl7au/au-fhir-inferno:5f0a3136416d718e5ef20e8a2381187d3569e4da-dev"       # use the image that is not tagged with -nginx
platformImageUri = "ghcr.io/hl7au/au-fhir-inferno:5f0a3136416d718e5ef20e8a2381187d3569e4da-nginx-dev" # use the image that IS tagged with -nginx
usesWrapper      = true
cluster_name     = "sparked-k8s"
vpc_name         = "sparked-k8s-vpc"
