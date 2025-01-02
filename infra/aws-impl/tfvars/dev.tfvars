name        = "inferno"
environment = "dev"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:3a85fb439cbdf07a94de868ec16fa84a2f4982ca" # old working core image
imageUrl         = "ghcr.io/hl7au/au-fhir-inferno:473d92b2fbe8e78ec36f43ffdc1fb827b4f82445" # new inferno image that has core bundled in?
platformImageUri = "ghcr.io/hl7au/au-fhir-inferno:7a99baaf50e18e201e95f7ca91477bc41da0cda8-nginx"
usesWrapper      = true
cluster_name     = "sparked-k8s"
vpc_name         = "sparked-k8s-vpc"