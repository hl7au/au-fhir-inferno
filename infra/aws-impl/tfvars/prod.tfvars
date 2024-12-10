name                 = "inferno"
environment          = "prod"
external_domain_name = "inferno.hl7.org.au"
imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:bb8de66a310a6dcb800b71e9da83a2a6221346c3" # old working core image
# imageUrl             = "ghcr.io/hl7au/au-fhir-inferno:d487ba0292c9d5224413424c76ab8a7a3172945e" # new inferno image that has core bundled in?
platformImageUri     = "ghcr.io/hl7au/au-fhir-inferno:7a99baaf50e18e201e95f7ca91477bc41da0cda8-nginx"
usesWrapper           = false