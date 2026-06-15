# variables.tf
# Todas las variables de entrada del proyecto, con tipo, descripcion y valor
# por defecto. Cambiar valores aqui (o en terraform.tfvars) reconfigura todo.

# ----------------------------- Region / nombres -----------------------------

variable "region" {
  description = "Region de AWS donde se despliega toda la infraestructura."
  type        = string
  default     = "ca-central-1"
}

variable "region_short" {
  description = "Abreviatura de la region para la nomenclatura de recursos."
  type        = string
  default     = "cacentral1"
}

variable "proyecto" {
  description = "Nombre corto del proyecto (parte de la nomenclatura)."
  type        = string
  default     = "pmkt"
}

variable "operacion" {
  description = "Operacion o entorno (parte de la nomenclatura)."
  type        = string
  default     = "prod"
}

variable "num" {
  description = "Numero correlativo de la operacion (parte de la nomenclatura)."
  type        = string
  default     = "01"
}

variable "azs" {
  description = "Zonas de disponibilidad a usar (minimo 2 para alta disponibilidad)."
  type        = list(string)
  default     = ["ca-central-1a", "ca-central-1b"]
}

# --------------------------------- Redes ------------------------------------

variable "vpc_principal_cidr" {
  description = "CIDR de la VPC principal (apps, frontend, APIs)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_data_cidr" {
  description = "CIDR de la VPC secundaria (bodega de datos historica). No debe solapar con la principal."
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnets_principal" {
  description = "CIDRs de las subredes publicas de la VPC principal (una por AZ)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnets_principal" {
  description = "CIDRs de las subredes privadas de la VPC principal (una por AZ)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_subnets_data" {
  description = "CIDRs de las subredes privadas de la VPC de datos (una por AZ)."
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24"]
}

# -------------------------------- Computo -----------------------------------

variable "apps" {
  description = "Lista de microservicios/aplicaciones que corren en EC2."
  type        = list(string)
  default     = ["frontsite", "backoffice", "webapi", "gameapi"]
}

variable "ec2_instance_type" {
  description = "Tipo de instancia EC2 para las aplicaciones."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Puerto en el que escuchan las aplicaciones en las EC2."
  type        = number
  default     = 80
}

# ----------------------------- Bases de datos -------------------------------

variable "rds_instance_class" {
  description = "Clase de instancia para la RDS transaccional."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_engine" {
  description = "Motor de la base de datos RDS transaccional."
  type        = string
  default     = "postgres"
}

variable "rds_engine_version" {
  description = "Version del motor RDS."
  type        = string
  default     = "16.3"
}

variable "db_username" {
  description = "Usuario administrador de las bases de datos (RDS y Redshift)."
  type        = string
  default     = "casino_admin"
}

variable "db_password" {
  description = "Contrasena de las bases de datos. Pasar via TF_VAR_db_password o tfvars; NUNCA versionar en Git."
  type        = string
  sensitive   = true
  default     = "ChangeMe2026Secure"
}

variable "redshift_node_type" {
  description = "Tipo de nodo para el cluster Redshift (bodega de datos)."
  type        = string
  default     = "dc2.large"
}

# --------------------------------- Cache ------------------------------------

variable "redis_node_type" {
  description = "Tipo de nodo para ElastiCache Redis."
  type        = string
  default     = "cache.t3.micro"
}

# ------------------------------ CloudFront / ACM ----------------------------

variable "domain_name" {
  description = "Dominio para el certificado ACM del ALB (debe existir para validar en un apply real)."
  type        = string
  default     = "casino.example.com"
}

# -------------------------------- Logging -----------------------------------

variable "elb_account_id" {
  description = "Account ID del servicio ELB en ca-central-1 (para la politica de access logs en S3)."
  type        = string
  default     = "985666609251"
}

variable "log_retention_days" {
  description = "Dias de retencion de los CloudWatch Log Groups."
  type        = number
  default     = 30
}

variable "enable_sns_endpoint" {
  description = "Crear tambien un Interface Endpoint para SNS (opcional)."
  type        = bool
  default     = false
}
