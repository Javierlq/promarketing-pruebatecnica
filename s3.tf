# s3.tf
# Dos buckets S3:
#   1. Contenido estatico: privado, cifrado SSE-KMS, accesible solo via CloudFront OAC.
#   2. ALB Access Logs: recibe los logs del balanceador (politica ELB obligatoria).

# =============================================================================
# BUCKET DE CONTENIDO ESTATICO

resource "aws_s3_bucket" "static" {
  # El account_id en el nombre garantiza unicidad global del bucket.
  bucket = "s3-static-${local.name_suffix}-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.tags, { Name = "s3-static-${local.name_suffix}" })
}

# Cifrado en reposo SSE-KMS con la clave creada en main.tf
resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

# Bloquear cualquier ACL publica o acceso anonimo al bucket
resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Politica del bucket: SOLO CloudFront (via OAC con SourceArn) puede leer objetos
resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOACReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.static.arn
          }
        }
      }
    ]
  })
}

# Versionado opcional: permite recuperar versiones anteriores de assets
resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# BUCKET DE ALB ACCESS LOGS
# El ALB escribe sus logs de acceso aqui

resource "aws_s3_bucket" "alb_logs" {
  bucket = "s3-alblogs-${local.name_suffix}-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.tags, { Name = "s3-alblogs-${local.name_suffix}" })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Politica obligatoria para que el servicio ELB pueda escribir access logs
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowELBLogDelivery"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.elb_account_id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}

# Ciclo de vida: los logs mas antiguos de 90 dias se eliminan automaticamente
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {
      prefix = "alb/"
    }

    expiration {
      days = 90
    }
  }
}
