# cloudfront.tf
# Origin Access Control (OAC) + distribucion CloudFront para servir el
# contenido estatico del bucket S3 privado a nivel global con baja latencia.

# =============================================================================
# ORIGIN ACCESS CONTROL (OAC)
# Reemplaza al OAI legacy. CloudFront firma cada peticion a S3 con SigV4,
# permitiendo el uso de SSE-KMS. Solo esta distribucion puede leer el bucket.


resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "oac-${local.name_suffix}"
  description                       = "OAC para el bucket S3 de contenido estatico del casino"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# =============================================================================
# DISTRIBUCION CLOUDFRONT

resource "aws_cloudfront_distribution" "static" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "CDN casino estatico - ${local.name_suffix}"
  price_class         = "PriceClass_100"

  # --- Origen: el bucket S3 privado -------------------------------------------
  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = "s3-static-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  # --- Comportamiento de cache por defecto ------------------------------------
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-static-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Politica de cache gestionada por AWS: optimizada para S3
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # --- Restricciones geograficas (ninguna por defecto) -------------------------
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # --- Certificado: el certificado por defecto de CloudFront (*.cloudfront.net) -
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # --- Pagina de error personalizada para 403/404 de S3 -----------------------
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  tags = merge(local.tags, { Name = "cf-${local.name_suffix}" })
}
