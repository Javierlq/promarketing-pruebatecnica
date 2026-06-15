# main.tf
# Configuracion base: proveedor AWS, datos comunes, nomenclatura (locals),
# clave KMS para SSE-KMS y certificado ACM del ALB.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Proveedor de AWS apuntando a la region del reto (ca-central-1 por defecto).
provider "aws" {
  region = var.region
}

# Datos de la cuenta actual (se usa el account_id para nombres de bucket unicos
# y para las politicas de IAM/KMS).
data "aws_caller_identity" "current" {}

# Lista de AZs disponibles en la region (informativo / validacion).
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Nomenclatura obligatoria del reto: recurso-proyecto-operacion-num-region
  name_suffix = "${var.proyecto}-${var.operacion}-${var.num}-${var.region_short}"

  # Tags comunes que se aplican (via merge) a todos los recursos.
  tags = {
    Project   = var.proyecto
    Operation = var.operacion
    ManagedBy = "Terraform"
    Challenge = "Promarketing-Cloud"
  }
}

# Clave KMS para cifrar en reposo (SSE-KMS) el bucket S3 de contenido estatico.

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

# Alias legible para la clave KMS.
resource "aws_kms_alias" "s3" {
  name          = "alias/s3-${local.name_suffix}"
  target_key_id = aws_kms_key.s3.key_id
}

# Certificado SSL/TLS para el ALB, emitido por ACM con validacion DNS.

resource "aws_acm_certificate" "alb" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = "acm-${local.name_suffix}" })
}
