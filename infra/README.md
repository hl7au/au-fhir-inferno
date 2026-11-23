# Infrastructure

How Inferno is deployed on the Sparked platform, and where each part lives:

| What | Where |
| --- | --- |
| The Helm chart | [hl7au/inferno-deployment](https://github.com/hl7au/inferno-deployment) |
| Per-environment values (sizing, hostnames, policy) and the Argo CD Applications | [aehrc/sparked-argo](https://github.com/aehrc/sparked-argo) |
| The AWS resources Inferno uses: the dev and prod RDS PostgreSQL instances, their security groups, and the IRSA role External Secrets uses to read the database credentials | [aehrc/sparked-infrastructure](https://github.com/aehrc/sparked-infrastructure), stack `terraform-inferno/` |

The Terraform was `infra/aws-impl/` here, with the `inferno-infra-deploy` workflow. A change to the database or the role is now a pull request in aehrc/sparked-infrastructure, which plans it and applies it by manual dispatch.
