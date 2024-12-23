name                 = "inferno"
environment          = "prod"
external_domain_name = "inferno.hl7.org.au"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:bb8de66a310a6dcb800b71e9da83a2a6221346c3" # old working core image
imageUrl         = "ghcr.io/hl7au/au-fhir-inferno:473d92b2fbe8e78ec36f43ffdc1fb827b4f82445" # new inferno image that has core bundled in?
platformImageUri = "ghcr.io/hl7au/au-fhir-inferno:473d92b2fbe8e78ec36f43ffdc1fb827b4f82445-nginx"
usesWrapper      = true