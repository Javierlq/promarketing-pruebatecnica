# Gateway Endpoint S3

data "aws_vpc_endpoint_service" "s3" {
  service      = "s3"
  service_type = "Gateway"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.principal.id
  service_name      = data.aws_vpc_endpoint_service.s3.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private_principal : rt.id]

  tags = merge(local.tags, { Name = "vpce-s3-${local.name_suffix}" })
}

# Interface Endpoint Secrets Manager

data "aws_vpc_endpoint_service" "secretsmanager" {
  service      = "secretsmanager"
  service_type = "Interface"
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.principal.id
  service_name        = data.aws_vpc_endpoint_service.secretsmanager.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private_principal : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "vpce-sm-${local.name_suffix}" })
}

# Interface Endpoint SNS (opcional)

data "aws_vpc_endpoint_service" "sns" {
  for_each     = toset(var.enable_sns_endpoint ? ["sns"] : [])
  service      = "sns"
  service_type = "Interface"
}

resource "aws_vpc_endpoint" "sns" {
  for_each            = toset(var.enable_sns_endpoint ? ["sns"] : [])
  vpc_id              = aws_vpc.principal.id
  service_name        = data.aws_vpc_endpoint_service.sns[each.key].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private_principal : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "vpce-sns-${local.name_suffix}" })
}
