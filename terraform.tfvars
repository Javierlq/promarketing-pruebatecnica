# Valores de ejemplo. No contiene secretos: la contrasena de la BD se genera
# con random_password y se guarda en Secrets Manager.

region       = "ca-central-1"
region_short = "cacentral1"
proyecto     = "pmkt"
operacion    = "prod"
num          = "01"
azs          = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]

vpc_principal_cidr        = "10.0.0.0/16"
vpc_data_cidr             = "10.1.0.0/16"
public_subnets_principal  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
private_subnets_principal = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
private_subnets_data      = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]

ec2_instance_type = "t3.micro"

rds_instance_class = "db.t3.micro"
rds_engine         = "postgres"
rds_engine_version = "16.3"
db_username        = "casino_admin"

redshift_base_capacity = 8
redis_node_type        = "cache.t3.micro"

domain_name = "casino.example.com"

# IMPORTANTE: para un apply real cambiar a true e indicar el ID de la zona Route53.
# Sin esto el certificado ACM queda pendiente de validacion y el listener HTTPS 443 fallara.
enable_acm_validation = false
route53_zone_id       = ""

log_retention_days  = 30
alarm_email         = ""
enable_sns_endpoint = false
