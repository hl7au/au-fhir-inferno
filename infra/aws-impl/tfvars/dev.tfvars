name        = "inferno"
environment = "dev"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:3a85fb439cbdf07a94de868ec16fa84a2f4982ca" # old working core image
imageUrl         = "ghcr.io/hl7au/au-fhir-inferno:280132451e49809330271a29260a1d060ae480ee-dev"       # use the image that is not tagged with -nginx
platformImageUri = "ghcr.io/hl7au/au-fhir-inferno:280132451e49809330271a29260a1d060ae480ee-nginx-dev" # use the image that IS tagged with -nginx
usesWrapper      = true
cluster_name     = "sparked-k8s"
vpc_name         = "sparked-k8s-vpc"
