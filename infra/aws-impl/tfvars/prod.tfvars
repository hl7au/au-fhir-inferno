name                 = "inferno"
environment          = "prod"
external_domain_name = "inferno.hl7.org.au"
# imageUrl             = "ghcr.io/hl7au/au-fhir-core-inferno:3a85fb439cbdf07a94de868ec16fa84a2f4982ca" # old working core image
imageUrl             = "ghcr.io/hl7au/au-fhir-inferno:10a03203c0e7219c95146190c69114db178d942c" # new inferno image that has core bundled in?
platformImageUri     = "ghcr.io/hl7au/au-fhir-inferno:7a99baaf50e18e201e95f7ca91477bc41da0cda8-nginx"