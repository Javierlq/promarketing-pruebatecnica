# terraform.tfvars
# Valores de ejemplo para el proyecto. No versionar este archivo si contiene
# passwords reales. Copiar a terraform.tfvars.local para valores sensibles.

region       = "ca-central-1"
region_short = "cacentral1"
proyecto     = "pmkt"
operacion    = "prod"
num          = "01"
azs          = ["ca-central-1a", "ca-central-1b"]

vpc_principal_cidr        = "10.0.0.0/16"
vpc_data_cidr             = "10.1.0.0/16"
public_subnets_principal  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnets_principal = ["10.0.10.0/24", "10.0.11.0/24"]
private_subnets_data      = ["10.1.10.0/24", "10.1.11.0/24"]

apps              = ["frontsite", "backoffice", "webapi", "gameapi"]
ec2_instance_type = "t3.micro"
app_port          = 80

rds_instance_class = "db.t3.micro"
rds_engine         = "postgres"
rds_engine_version = "16.3"
db_username        = "casino_admin"
# db_password se pasa via variable de entorno: export TF_VAR_db_password="..."

redshift_node_type = "dc2.large"
redis_node_type    = "cache.t3.micro"

domain_name        = "casino.example.com"
elb_account_id     = "985666609251"
log_retention_days = 30
enable_sns_endpoint = false
