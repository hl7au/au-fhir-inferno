# Infrastructure Setup

This directory contains the infrastructure-as-code for the AU FHIR Inferno application, including AWS resources provisioned via Terraform and Kubernetes deployments managed through Helm charts and ArgoCD.

## Overview

The infrastructure is divided into two main components:

1. **Terraform** ([aws-impl/](aws-impl/)) - Provisions AWS infrastructure including RDS PostgreSQL database and IAM roles
2. **Helm Charts** ([helm/inferno/](helm/inferno/)) - Kubernetes application deployment configurations

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                       ArgoCD                             │
│  https://argo.sparked-fhir.com/                         │
│                                                          │
│  Dev (staging) → `master` chart + values-dev; image     │
│                  tag written by ArgoCD Image Updater    │
│  Prod          → `master` chart + values-prod           │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              Helm Chart Deployment                       │
│  - Inferno Application (inferno-helmd)                  │
│  - PostgreSQL (Bitnami dependency)                      │
│  - HTTPRoutes on the shared Envoy Gateway               │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              AWS Infrastructure                          │
│  - RDS PostgreSQL 16 (major version pin)                │
│  - IAM Roles (IRSA for External Secrets)                │
│  - Security Groups                                       │
│  - VPC Configuration                                     │
└─────────────────────────────────────────────────────────┘
```

## Terraform Infrastructure

### Location
[aws-impl/](aws-impl/)

### Resources Provisioned

#### RDS PostgreSQL Database
- **Engine**: PostgreSQL, pinned to major version `16` (`engine_version` in `main.tf`); auto minor version upgrades move the minor forward
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
| `usesWrapper` | Whether app is an Inferno wrapper | Required |
| `deletion_protection` | RDS deletion protection | `false` |

Image references are not Terraform variables: they live in the Helm values as
`inferno.imageUrl` and `inferno.validatorImageUri` (see `tfvars/*.tfvars`, which mark
them as moved). The separate `platformImageUri` was removed with the nginx static-site
container; the application image now serves the static site itself.

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

## Helm Charts

### Location
[helm/inferno/](helm/inferno/)

### Chart Details
- **Name**: `inferno-helmd`
- **Version**: 0.2.0
- **App Version**: 1.16.0

### Dependencies
1. **PostgreSQL** (Bitnami)
   - Version: 15.5.17
   - Repository: https://charts.bitnami.com/bitnami
   - Conditional: `postgresql.enabled`, which is on only for the ci-build environment and
     previews; staging and production use RDS. `values.yaml` sets the subchart's
     `primary.resources` (requests, a memory limit and no CPU limit) in place of its
     `nano` preset, whose 150m CPU limit throttled an idle Postgres.

Routing is not a chart dependency: the chart renders Gateway API `HTTPRoute`s
(`templates/configs/inferno-httproute.yaml`) attached to the cluster's shared Envoy
Gateway, and the application serves the static site and Inferno itself on port 4567.

### Environment-Specific Values

#### Development Environment (staging)
- **Values File**: [values-dev.yaml](helm/inferno/values-dev.yaml)
- **Branch**: `master` (there is no separate `dev` branch; `master` is the trunk)
- **ArgoCD**: The `inferno-dev` Application (`apps/inferno-dev.yaml` in
  `aehrc/sparked-argo`) renders the chart from `master`. ArgoCD Image Updater writes
  the staging image tag to `apps/inferno-dev/image-values.yaml` in that repo, which
  overrides the image in `values-dev.yaml`.

#### Production Environment
- **Values File**: [values-prod.yaml](helm/inferno/values-prod.yaml)
- **Branch**: `master`
- **ArgoCD**: The `inferno-prod` Application renders the chart and `values-prod.yaml`
  from `master`. The prod image changes only through a merged promotion PR (see
  [docs/prod-releases.md](../docs/prod-releases.md)); chart changes reach prod when
  they merge to `master`.

#### CI-build Environment
- **Values File**: [values-ci-build.yaml](helm/inferno/values-ci-build.yaml)
- **Branch**: `master`
- **ArgoCD**: The `inferno-ci-build` Application (`apps/inferno-ci-build.yaml` in
  `aehrc/sparked-argo`) renders the chart from `master`; ArgoCD Image Updater writes the
  image tag to `apps/inferno-ci-build/image-values.yaml`. It runs each kit's CI-build
  suite on an in-namespace Postgres; see
  [docs/ci-build-environment.md](../docs/ci-build-environment.md).

### Deployment Process

All deployments are managed through **ArgoCD** at https://argo.sparked-fhir.com/

1. **Commit Changes**: Merge Helm chart or value changes to `master` through a PR
   - Dev: `values-dev.yaml` (the staging image tag is managed by ArgoCD Image Updater)
   - Prod: `values-prod.yaml` (the image is changed by the promotion PR)

2. **ArgoCD Sync**: ArgoCD automatically detects changes and syncs the application

3. **Verification**: Check deployment status in ArgoCD UI

### Manual Helm Operations

If you need to test Helm charts locally:

```bash
cd infra/helm/inferno

# Update dependencies
helm dependency update

# Lint the chart
helm lint .

# Dry run for development
helm install inferno . --values values-dev.yaml --dry-run --debug

# Dry run for production
helm install inferno . --values values-prod.yaml --dry-run --debug
```

## Secrets Management

The application uses **AWS External Secrets Operator** to fetch RDS credentials from AWS Secrets Manager:

1. Terraform creates RDS instance with managed master password in Secrets Manager
2. Terraform creates IAM role with IRSA for External Secrets service account
3. Kubernetes External Secrets controller uses this role to fetch credentials
4. Credentials are injected into application pods as Kubernetes secrets

## Environment Configuration

### Development
- **Namespace**: `dev-inferno`
- **Branch**: `master`
- **Values**: `values-dev.yaml`
- **ArgoCD**: Auto-sync enabled

### Production
- **Namespace**: `prod-inferno`
- **Branch**: `master`
- **Values**: `values-prod.yaml`
- **ArgoCD**: Auto-sync enabled with production safeguards

### CI-build
- **Namespace**: `ci-build-inferno`
- **Branch**: `master`
- **Values**: `values-ci-build.yaml`
- **ArgoCD**: Auto-sync enabled

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Helm >= 3.0
- kubectl configured for target EKS cluster
- Access to ArgoCD UI (https://argo.sparked-fhir.com/)

## Common Operations

### Update Application Image

- Dev (staging): merging to `master` builds a new image and ArgoCD Image Updater
  deploys it; no values change is needed.
- Prod: merge the promotion PR, which updates `inferno.imageUrl` in
  `helm/inferno/values-prod.yaml` (see [docs/prod-releases.md](../docs/prod-releases.md)).
  ArgoCD syncs the change automatically.

### Scale RDS Instance

1. Update `postgres_instance_class` in Terraform variables
2. Run `terraform plan` and `terraform apply`
3. RDS will be updated with minimal downtime

### Restore from RDS Snapshot

1. Set `snapshot_identifier` variable to the snapshot ID
2. Run `terraform apply`
3. Update application configuration if database name changed

## Monitoring & Troubleshooting

- **ArgoCD UI**: https://argo.sparked-fhir.com/ - Check deployment status and sync history
- **RDS Performance Insights**: Enabled with 7-day retention for database performance monitoring
- **Kubernetes Logs**: Check pod logs for application issues
  ```bash
  kubectl logs -n <namespace> -l app=inferno
  ```

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
