###############################################################################
# endpoints.tf
# VPC Endpoints: permiten que los recursos en subredes PRIVADAS accedan a
# servicios AWS sin salir a Internet (mas seguro y sin coste de NAT).

# =============================================================================
# GATEWAY ENDPOINT PARA S3
# Tipo Gateway: no crea una IP privada, sino que agrega una entrada en las
# route tables indicando "el trafico a S3 va por AWS internamente, no por NAT".

data "aws_vpc_endpoint_service" "s3" {
  service      = "s3"
  service_type = "Gateway"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.principal.id
  service_name      = data.aws_vpc_endpoint_service.s3.service_name
  vpc_endpoint_type = "Gateway"

  # Asociar a las route tables de las subredes privadas (no publicas,
  # porque el ALB no necesita acceder a S3 internamente).
  route_table_ids = [aws_route_table.private_principal.id]

  tags = merge(local.tags, { Name = "vpce-s3-${local.name_suffix}" })
}

# =============================================================================
# INTERFACE ENDPOINT PARA SECRETS MANAGER
# Tipo Interface: crea una Elastic Network Interface (ENI) con IP privada
# dentro de la VPC. Las EC2 acceden a Secrets Manager (para obtener passwords)
# sin que el trafico salga a Internet.

data "aws_vpc_endpoint_service" "secretsmanager" {
  service      = "secretsmanager"
  service_type = "Interface"
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.principal.id
  service_name        = data.aws_vpc_endpoint_service.secretsmanager.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_principal[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "vpce-sm-${local.name_suffix}" })
}

# =============================================================================
# INTERFACE ENDPOINT PARA SNS (opcional)
# Solo se crea si var.enable_sns_endpoint = true.

data "aws_vpc_endpoint_service" "sns" {
  count        = var.enable_sns_endpoint ? 1 : 0
  service      = "sns"
  service_type = "Interface"
}

resource "aws_vpc_endpoint" "sns" {
  count               = var.enable_sns_endpoint ? 1 : 0
  vpc_id              = aws_vpc.principal.id
  service_name        = data.aws_vpc_endpoint_service.sns[0].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_principal[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "vpce-sns-${local.name_suffix}" })
}
