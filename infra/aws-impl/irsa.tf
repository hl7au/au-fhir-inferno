data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# IAM Role for External Secrets Service Account
resource "aws_iam_role" "external_secrets_sa" {
  name = "${local.env_name}-external-secrets-sa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${local.env_name}:external-secrets-sa"
          "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

# IAM Policy for accessing the RDS secret
resource "aws_iam_role_policy" "external_secrets_policy" {
  name = "${local.env_name}-external-secrets-policy"
  role = aws_iam_role.external_secrets_sa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          module.rds.db_instance_master_user_secret_arn
        ]
      }
    ]
  })
}

# Output the IAM role ARN for reference
output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets_sa.arn
}

output "rds_secret_arn" {
  value = module.rds.db_instance_master_user_secret_arn
}