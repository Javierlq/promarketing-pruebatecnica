terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_suffix = "${var.proyecto}-${var.operacion}-${var.num}-${var.region_short}"

  servicios_infra = {
    frontsite  = { port = 80, path = "/*" }
    backoffice = { port = 8080, path = "/backoffice/*" }
    webapi     = { port = 8081, path = "/api/*" }
    gameapi    = { port = 8082, path = "/game/*" }
  }

  private_subnet_ids = [for az in var.azs : aws_subnet.private_principal[az].id]

  tags = {
    Project   = var.proyecto
    Operation = var.operacion
    ManagedBy = "Terraform"
    Challenge = "Promarketing-Cloud"
  }
}

# KMS

resource "aws_kms_key" "s3" {
  description             = "KMS key para SSE-KMS del bucket S3 estatico"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudFrontDecrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = ["kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.static.arn
          }
        }
      }
    ]
  })

  tags = merge(local.tags, { Name = "kms-s3-${local.name_suffix}" })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/s3-${local.name_suffix}"
  target_key_id = aws_kms_key.s3.key_id
}

# Secrets Manager — credenciales generadas con random_password

resource "random_password" "db_pass" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "casino-db-secret-${local.name_suffix}"
  description             = "Credenciales de RDS y Redshift del casino"
  recovery_window_in_days = 0

  tags = merge(local.tags, { Name = "secret-db-${local.name_suffix}" })
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_pass.result
    database = "casino_db"
  })
}

# ACM + validacion DNS (opcional via Route53)

resource "aws_acm_certificate" "alb" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = "acm-${local.name_suffix}" })
}

data "aws_route53_zone" "main" {
  for_each = toset(var.enable_acm_validation ? ["main"] : [])
  zone_id  = var.route53_zone_id
}

resource "aws_route53_record" "acm_validation" {
  for_each = var.enable_acm_validation ? {
    for dvo in aws_acm_certificate.alb.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = data.aws_route53_zone.main["main"].zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "alb" {
  for_each                = toset(var.enable_acm_validation ? ["main"] : [])
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
