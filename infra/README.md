# Infrastructure

This directory holds only the Terraform for the AWS resources production Inferno uses on
the Sparked platform (RDS PostgreSQL and the IRSA role External Secrets uses to read its
credentials), in [aws-impl/](aws-impl/). The `inferno-infra-deploy` workflow plans it on
PRs and applies it only by manual dispatch.

Everything else about how Inferno is deployed lives elsewhere:

| What | Where |
| --- | --- |
| The Helm chart, its CI and the docker-compose example | [hl7au/inferno-deployment](https://github.com/hl7au/inferno-deployment) |
| Per-environment values (sizing, hostnames, policy) and the Argo CD Applications | [aehrc/sparked-argo](https://github.com/aehrc/sparked-argo) (`apps/inferno-*`) |
| The image production runs | [`deploy/prod-image.yaml`](../deploy/prod-image.yaml), bumped by the prod-promotion PR; see [docs/prod-releases.md](../docs/prod-releases.md) |

A change to sizing or probes is a sparked-argo PR. A change to what the chart can do is an
inferno-deployment PR and release, then a chart version bump in sparked-argo.

## Terraform Infrastructure

### Location
[aws-impl/](aws-impl/)

### Resources Provisioned

#### RDS PostgreSQL Database
- **Engine**: PostgreSQL 16.8
- **Instance Class**: Configurable (default: `db.t4g.small`)
- **Storage**: 20 GB allocated
- **Database Name**: `inferno`
- **Features**:
  - Performance Insights enabled (7-day retention)
  - Automated master password management via AWS Secrets Manager
  - VPC-based security groups
  - Maintenance window: Monday 00:00-03:00 UTC

#### IAM Roles (IRSA)
- **External Secrets Service Account Role**: Allows Kubernetes pods to retrieve RDS credentials from AWS Secrets Manager
- **Permissions**:
  - `secretsmanager:GetSecretValue`
  - `secretsmanager:DescribeSecret`

#### Security Groups
- PostgreSQL access restricted to VPC CIDR block (port 5432)

### Terraform Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `region` | AWS region | `ap-southeast-2` |
| `cluster_name` | EKS cluster name | `fhir-k8s-dev` |
| `vpc_name` | VPC name | `fhir-k8s-dev-vpc` |
| `environment` | Environment name | `dev` |
| `name` | Application name | `inferno` |
| `rds_name` | RDS instance name | `{environment}-{name}-postgresql` |
| `postgres_instance_class` | RDS instance type | `db.t4g.small` |
| `snapshot_identifier` | Optional RDS snapshot for restore | `null` |
| `imageUrl` | Application image URL | Required |
| `platformImageUri` | Platform image URI | Required |
| `validatorImageUri` | Validator image URI | `markiantorno/validator-wrapper:1.0.78` |
| `usesWrapper` | Whether app is an Inferno wrapper | Required |

### Terraform Outputs

- `external_secrets_role_arn`: ARN of the IAM role for External Secrets
- `rds_secret_arn`: ARN of the RDS master password secret in Secrets Manager

### Usage

```bash
cd infra/aws-impl

# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Get outputs
terraform output
```

## Common operations

### Scale RDS instance

1. Update `postgres_instance_class` in Terraform variables
2. Run `terraform plan` and `terraform apply`
3. RDS will be updated with minimal downtime

### Restore from RDS snapshot

1. Set `snapshot_identifier` variable to the snapshot ID
2. Run `terraform apply`
3. Update application configuration if database name changed

## Tags

All AWS resources are tagged with:
- `Name`: `{environment}-{name}`
- `GithubRepo`: `https://github.com/hl7au/au-fhir-inferno`

## Support

For issues or questions:
- Check ArgoCD sync status
- Review Terraform state for infrastructure issues
- Consult application logs in Kubernetes
- Review AWS CloudWatch logs for RDS and IAM issues
