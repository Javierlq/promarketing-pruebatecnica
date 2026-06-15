# Reto Técnico — Ingeniero Cloud | Promarketing Chile

Infraestructura AWS para una operación de Casino Online, diseñada y aprovisionada con Terraform siguiendo los principios del **AWS Well-Architected Framework**: seguridad, alta disponibilidad, eficiencia de rendimiento y optimización de costos.

---

## Arquitectura

[Ver diagrama interactivo en draw.io](https://drive.google.com/file/d/1ZCdB5hC2ayMMV3HYqD-n2qS_Ae6BqvyX/view?usp=sharing)

---

## Estructura del Repositorio

```
.
├── main.tf               # Provider AWS ~>5.0, KMS CMK, ACM
├── variables.tf          # Variables con valores por defecto
├── outputs.tf            # 15 outputs (endpoints, ARNs, DNS)
├── network.tf            # VPCs, subredes, IGW, NAT, Route Tables, SGs, NACLs
├── instances.tf          # ALB, EC2 x4, RDS PostgreSQL, Redshift, ElastiCache Redis
├── s3.tf                 # S3 estático (SSE-KMS) y S3 ALB Logs (lifecycle)
├── cloudfront.tf         # OAC + distribución CloudFront
├── endpoints.tf          # VPC Endpoints: S3 Gateway + Secrets Manager Interface
├── monitoring.tf         # CloudWatch Log Groups + alarmas 5xx y latencia
├── terraform.tfvars      # Valores de ejemplo para despliegue
├── diagrama/
│   ├── Arquitectura-AWS-Promarketing-Casino-Online-Arquitectura Lógica.jpg
│   └── Enlace Drawio.txt
└── costos/
    └── calculadora-costos.xlsx
```

---

## Despliegue

### Prerrequisitos

- Terraform >= 1.5
- AWS CLI configurado con credenciales válidas para `ca-central-1`
- Dominio con registro DNS para validación del certificado ACM

### Comandos

```bash
# Inicializar providers y módulos
terraform init

# Revisar el plan de ejecución
terraform plan

# Aprovisionar la infraestructura
terraform apply

# Destruir la infraestructura
terraform destroy
```

> **Nota:** El certificado ACM requiere validación DNS manual antes de que el ALB quede operativo. Los outputs del `terraform apply` entregan los registros CNAME necesarios para la validación.

---

## Referencias

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Pricing Calculator](https://calculator.aws/pricing/2/home)
