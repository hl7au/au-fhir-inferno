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
│  Dev Environment  → watches `dev` branch (values-dev)   │
│  Prod Environment → watches `master` branch (values-prod)│
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              Helm Chart Deployment                       │
│  - Inferno Application (inferno-helmd)                  │
│  - PostgreSQL (Bitnami dependency)                      │
│  - Ingress NGINX (ingress-nginx)                        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│              AWS Infrastructure                          │
│  - RDS PostgreSQL 16.8                                  │
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
| `validatorImageUri` | Validator image URI | `markiantorno/validator-wrapper:1.0.68` |
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
   - Conditional: `postgresql.enabled`

2. **Ingress NGINX**
   - Version: 4.11.1
   - Repository: https://kubernetes.github.io/ingress-nginx
   - Conditional: `controller.enabled`

### Environment-Specific Values

#### Development Environment
- **Values File**: [values-dev.yaml](helm/inferno/values-dev.yaml)
- **Branch**: `dev`
- **ArgoCD**: Watches `dev` branch for automatic deployments

#### Production Environment
- **Values File**: [values-prod.yaml](helm/inferno/values-prod.yaml)
- **Branch**: `master`
- **ArgoCD**: Watches `master` branch for automatic deployments

### Deployment Process

All deployments are managed through **ArgoCD** at https://argo.sparked-fhir.com/

1. **Commit Changes**: Push Helm value changes to the appropriate branch
   - Dev changes → `dev` branch with `values-dev.yaml`
   - Prod changes → `master` branch with `values-prod.yaml`

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
- **Branch**: `dev`
- **Values**: `values-dev.yaml`
- **ArgoCD**: Auto-sync enabled

### Production
- **Namespace**: `prod-inferno` (or similar)
- **Branch**: `master`
- **Values**: `values-prod.yaml`
- **ArgoCD**: Auto-sync enabled with production safeguards

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Helm >= 3.0
- kubectl configured for target EKS cluster
- Access to ArgoCD UI (https://argo.sparked-fhir.com/)

## Common Operations

### Update Application Image

1. Update the image reference in the appropriate values file:
   - Dev: `helm/inferno/values-dev.yaml`
   - Prod: `helm/inferno/values-prod.yaml`

2. Commit and push to the corresponding branch
3. ArgoCD will automatically sync the changes

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
