# --------------------------------- VPCs -------------------------------------

output "vpc_principal_id" {
  description = "ID de la VPC principal (apps, frontend, APIs)."
  value       = aws_vpc.principal.id
}

output "vpc_data_id" {
  description = "ID de la VPC secundaria (bodega de datos Redshift)."
  value       = aws_vpc.data.id
}

output "vpc_peering_id" {
  description = "ID de la conexion de VPC Peering entre ambas VPCs."
  value       = aws_vpc_peering_connection.principal_to_data.id
}

# ------------------------------- Subredes -----------------------------------

output "public_subnet_ids" {
  description = "IDs de las subredes publicas de la VPC principal (donde vive el ALB)."
  value       = [for s in aws_subnet.public_principal : s.id]
}

output "private_subnet_ids_principal" {
  description = "IDs de las subredes privadas de la VPC principal (EC2, RDS, Redis)."
  value       = [for s in aws_subnet.private_principal : s.id]
}

output "private_subnet_ids_data" {
  description = "IDs de las subredes privadas de la VPC de datos (Redshift)."
  value       = [for s in aws_subnet.private_data : s.id]
}

# --------------------------------- ALB --------------------------------------

output "alb_dns_name" {
  description = "DNS del Application Load Balancer. Apunta tu dominio aqui con un CNAME."
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Hosted Zone ID del ALB (para alias records en Route 53)."
  value       = aws_lb.main.zone_id
}

# --------------------------------- Computo ----------------------------------

output "asg_names" {
  description = "Mapa nombre-de-app -> Nombre del Auto Scaling Group."
  value       = { for app, asg in aws_autoscaling_group.app : app => asg.name }
}

output "target_group_arns" {
  description = "Mapa nombre-de-app -> ARN del Target Group del ALB."
  value       = { for app, tg in aws_lb_target_group.app : app => tg.arn }
}

# --------------------------------- RDS --------------------------------------

output "rds_endpoint" {
  description = "Endpoint de conexion de la RDS transaccional (host:puerto)."
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

# -------------------------------- Redshift ----------------------------------

output "redshift_endpoint" {
  description = "Endpoint del workgroup de Redshift Serverless (bodega de datos historica)."
  value       = aws_redshiftserverless_workgroup.data.endpoint
  sensitive   = true
}

# --------------------------------- Redis ------------------------------------

output "redis_endpoint" {
  description = "Endpoint primario de ElastiCache Redis."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive   = true
}

# ---------------------------------- S3 --------------------------------------

output "s3_static_bucket_name" {
  description = "Nombre del bucket S3 de contenido estatico (privado, cifrado con KMS)."
  value       = aws_s3_bucket.static.bucket
}

output "s3_logs_bucket_name" {
  description = "Nombre del bucket S3 que recibe los access logs del ALB."
  value       = aws_s3_bucket.alb_logs.bucket
}

# ------------------------------ CloudFront ----------------------------------

output "cloudfront_domain" {
  description = "Dominio de la distribucion CloudFront para servir contenido estatico."
  value       = aws_cloudfront_distribution.static.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID de la distribucion CloudFront (util para invalidaciones de cache)."
  value       = aws_cloudfront_distribution.static.id
}

# --------------------------------- KMS --------------------------------------

output "kms_key_arn" {
  description = "ARN de la clave KMS usada para SSE-KMS en S3."
  value       = aws_kms_key.s3.arn
}

# ------------------------------ Secrets / Endpoints -------------------------

output "db_secret_arn" {
  description = "ARN del secreto en Secrets Manager con las credenciales de la BD."
  value       = aws_secretsmanager_secret.db_secret.arn
}

output "vpc_endpoint_s3_id" {
  description = "ID del VPC Endpoint Gateway para S3 (trafico privado sin pasar por Internet)."
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_secretsmanager_id" {
  description = "ID del VPC Endpoint Interface para Secrets Manager."
  value       = aws_vpc_endpoint.secretsmanager.id
}
