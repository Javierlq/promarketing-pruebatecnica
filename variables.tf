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
  description = "Zonas de disponibilidad a usar (minimo 3 para Redshift Serverless y alta disponibilidad)."
  type        = list(string)
  default     = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]

  validation {
    condition     = length(var.azs) >= 3
    error_message = "Se requieren al menos 3 AZs (Redshift Serverless exige subredes en 3 AZs)."
  }
}

# --------------------------------- Redes ------------------------------------

variable "vpc_principal_cidr" {
  description = "CIDR de la VPC principal (apps, frontend, APIs)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_principal_cidr))
    error_message = "vpc_principal_cidr debe ser un CIDR IPv4 valido."
  }
}

variable "vpc_data_cidr" {
  description = "CIDR de la VPC secundaria (bodega de datos historica). No debe solapar con la principal."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_data_cidr))
    error_message = "vpc_data_cidr debe ser un CIDR IPv4 valido."
  }
}

variable "public_subnets_principal" {
  description = "CIDRs de las subredes publicas de la VPC principal (una por AZ)."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = alltrue([for c in var.public_subnets_principal : can(cidrnetmask(c))])
    error_message = "Todos los CIDRs de public_subnets_principal deben ser validos."
  }
}

variable "private_subnets_principal" {
  description = "CIDRs de las subredes privadas de la VPC principal (una por AZ)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = alltrue([for c in var.private_subnets_principal : can(cidrnetmask(c))])
    error_message = "Todos los CIDRs de private_subnets_principal deben ser validos."
  }
}

variable "private_subnets_data" {
  description = "CIDRs de las subredes privadas de la VPC de datos (una por AZ)."
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]

  validation {
    condition     = alltrue([for c in var.private_subnets_data : can(cidrnetmask(c))])
    error_message = "Todos los CIDRs de private_subnets_data deben ser validos."
  }
}

# -------------------------------- Computo -----------------------------------

variable "ec2_instance_type" {
  description = "Tipo de instancia EC2 para las aplicaciones."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = length(trimspace(var.ec2_instance_type)) > 0
    error_message = "ec2_instance_type no puede estar vacio."
  }
}

# ----------------------------- Bases de datos -------------------------------

variable "rds_instance_class" {
  description = "Clase de instancia para la RDS transaccional."
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = length(trimspace(var.rds_instance_class)) > 0
    error_message = "rds_instance_class no puede estar vacio."
  }
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

variable "redshift_base_capacity" {
  description = "Capacidad base (RPU) del workgroup de Redshift Serverless."
  type        = number
  default     = 8

  validation {
    condition     = var.redshift_base_capacity >= 8
    error_message = "La capacidad base minima de Redshift Serverless es 8 RPU."
  }
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

variable "enable_acm_validation" {
  description = "Activa la validacion DNS automatica del certificado ACM via Route53 (requiere zona propia)."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "ID de la zona Route53 donde se crean los registros de validacion del certificado ACM."
  type        = string
  default     = ""
}

# -------------------------------- Logging -----------------------------------

variable "log_retention_days" {
  description = "Dias de retencion de los CloudWatch Log Groups."
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Correo que recibe las notificaciones SNS de las alarmas de CloudWatch."
  type        = string
  default     = ""
}

variable "enable_sns_endpoint" {
  description = "Crear tambien un Interface Endpoint para SNS (opcional)."
  type        = bool
  default     = false
}
