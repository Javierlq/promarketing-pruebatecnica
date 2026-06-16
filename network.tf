# VPCs

resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_principal_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "vpc-${local.name_suffix}" })
}

resource "aws_vpc" "data" {
  cidr_block           = var.vpc_data_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "vpc-data-${local.name_suffix}" })
}

# Subredes (una por AZ)

resource "aws_subnet" "public_principal" {
  for_each = { for i, az in var.azs : az => var.public_subnets_principal[i] }

  vpc_id                  = aws_vpc.principal.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "sbn-pub-${each.key}-${local.name_suffix}" })
}

resource "aws_subnet" "private_principal" {
  for_each = { for i, az in var.azs : az => var.private_subnets_principal[i] }

  vpc_id            = aws_vpc.principal.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(local.tags, { Name = "sbn-priv-${each.key}-${local.name_suffix}" })
}

resource "aws_subnet" "private_data" {
  for_each = { for i, az in var.azs : az => var.private_subnets_data[i] }

  vpc_id            = aws_vpc.data.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(local.tags, { Name = "sbn-data-${each.key}-${local.name_suffix}" })
}

# Gateways (IGW + un NAT por AZ)

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.principal.id

  tags = merge(local.tags, { Name = "igw-${local.name_suffix}" })
}

resource "aws_eip" "nat" {
  for_each = toset(var.azs)
  domain   = "vpc"

  tags = merge(local.tags, { Name = "eip-nat-${each.key}-${local.name_suffix}" })
}

resource "aws_nat_gateway" "main" {
  for_each = toset(var.azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public_principal[each.key].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.tags, { Name = "nat-${each.key}-${local.name_suffix}" })
}

# Tablas de ruteo

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, { Name = "rtb-pub-${local.name_suffix}" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public_principal

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_principal" {
  for_each = toset(var.azs)

  vpc_id = aws_vpc.principal.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[each.key].id
  }

  route {
    cidr_block                = var.vpc_data_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.principal_to_data.id
  }

  tags = merge(local.tags, { Name = "rtb-priv-${each.key}-${local.name_suffix}" })
}

resource "aws_route_table_association" "private_principal" {
  for_each = aws_subnet.private_principal

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_principal[each.key].id
}

resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.data.id

  route {
    cidr_block                = var.vpc_principal_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.principal_to_data.id
  }

  tags = merge(local.tags, { Name = "rtb-data-${local.name_suffix}" })
}

resource "aws_route_table_association" "private_data" {
  for_each = aws_subnet.private_data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_data.id
}

# VPC Peering

resource "aws_vpc_peering_connection" "principal_to_data" {
  vpc_id      = aws_vpc.principal.id
  peer_vpc_id = aws_vpc.data.id
  auto_accept = true

  tags = merge(local.tags, { Name = "peer-${local.name_suffix}" })
}

# Security Groups

resource "aws_security_group" "alb" {
  name        = "alb-${local.name_suffix}"
  description = "Trafico entrante HTTPS/HTTP desde Internet hacia el ALB"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description = "HTTPS desde Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP desde Internet (redirige a HTTPS via listener)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida hacia EC2 solo en puertos de servicio (target groups)"
    from_port   = 80
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = [var.vpc_principal_cidr]
  }

  tags = merge(local.tags, { Name = "sg-alb-${local.name_suffix}" })
}

resource "aws_security_group" "ec2" {
  name_prefix = "ec2-${local.name_suffix}"
  description = "Trafico entrante solo desde el ALB hacia las instancias EC2"
  vpc_id      = aws_vpc.principal.id

  dynamic "ingress" {
    for_each = toset([for s in local.servicios_infra : s.port])
    content {
      description     = "Trafico del servicio en el puerto ${ingress.value} solo desde el ALB"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  egress {
    description = "HTTPS hacia Secrets Manager (endpoint) e Internet via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "PostgreSQL hacia RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_principal_cidr]
  }

  egress {
    description = "Redis hacia ElastiCache"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_principal_cidr]
  }

  egress {
    description = "Redshift via VPC Peering"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.vpc_data_cidr]
  }

  tags = merge(local.tags, { Name = "sg-ec2-${local.name_suffix}" })
}

resource "aws_security_group" "redis" {
  name_prefix = "redis-${local.name_suffix}"
  description = "Puerto Redis (6379) solo accesible desde las instancias EC2"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "Redis desde EC2"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(local.tags, { Name = "sg-redis-${local.name_suffix}" })
}

resource "aws_security_group" "rds" {
  name_prefix = "rds-${local.name_suffix}"
  description = "Puerto PostgreSQL (5432) solo accesible desde las instancias EC2"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "PostgreSQL desde EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(local.tags, { Name = "sg-rds-${local.name_suffix}" })
}

resource "aws_security_group" "redshift" {
  name        = "redshift-${local.name_suffix}"
  description = "Puerto Redshift (5439) accesible desde la VPC principal via peering"
  vpc_id      = aws_vpc.data.id

  ingress {
    description = "Redshift desde VPC principal (EC2 via peering)"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.vpc_principal_cidr]
  }

  tags = merge(local.tags, { Name = "sg-redshift-${local.name_suffix}" })
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "vpce-${local.name_suffix}"
  description = "HTTPS (443) desde subredes privadas hacia VPC Interface Endpoints"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description = "HTTPS desde subredes privadas"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.private_subnets_principal
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "sg-vpce-${local.name_suffix}" })
}

# Network ACLs

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.principal.id
  subnet_ids = [for s in aws_subnet.public_principal : s.id]

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 65535
  }

  tags = merge(local.tags, { Name = "nacl-pub-${local.name_suffix}" })
}

resource "aws_network_acl" "private_principal" {
  vpc_id     = aws_vpc.principal.id
  subnet_ids = [for s in aws_subnet.private_principal : s.id]

  dynamic "ingress" {
    for_each = { for i, p in distinct([for s in local.servicios_infra : s.port]) : i => p }
    content {
      rule_no    = 100 + ingress.key
      protocol   = "tcp"
      action     = "allow"
      cidr_block = var.vpc_principal_cidr
      from_port  = ingress.value
      to_port    = ingress.value
    }
  }

  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 65535
  }

  tags = merge(local.tags, { Name = "nacl-priv-${local.name_suffix}" })
}

resource "aws_network_acl" "private_data" {
  vpc_id     = aws_vpc.data.id
  subnet_ids = [for s in aws_subnet.private_data : s.id]

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_principal_cidr
    from_port  = 5439
    to_port    = 5439
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_principal_cidr
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_principal_cidr
    from_port  = 0
    to_port    = 65535
  }

  tags = merge(local.tags, { Name = "nacl-data-${local.name_suffix}" })
}
