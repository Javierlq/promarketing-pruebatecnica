# network.tf
# Toda la capa de red: 2 VPCs, subredes, IGW, NAT Gateway, VPC Peering,
# tablas de ruteo, Security Groups y Network ACLs.

# =============================================================================
# VPC PRINCIPAL — aplicaciones, frontend, APIs y servicios publicos

resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_principal_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "vpc-${local.name_suffix}" })
}

# =============================================================================
# VPC SECUNDARIA — bodega de datos historica (Redshift)

resource "aws_vpc" "data" {
  cidr_block           = var.vpc_data_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "vpc-data-${local.name_suffix}" })
}

# =============================================================================
# SUBREDES — VPC principal: publicas (ALB) y privadas (EC2/RDS/Redis)
# count = 2 crea una subred por AZ para alta disponibilidad

resource "aws_subnet" "public_principal" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.principal.id
  cidr_block        = var.public_subnets_principal[count.index]
  availability_zone = var.azs[count.index]

  # Las subredes publicas NO asignan IP publica automaticamente a las instancias.
  # Solo el ALB vive aqui; las EC2 van a privadas.
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "sbn-pub-${count.index + 1}-${local.name_suffix}" })
}

resource "aws_subnet" "private_principal" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.principal.id
  cidr_block        = var.private_subnets_principal[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.tags, { Name = "sbn-priv-${count.index + 1}-${local.name_suffix}" })
}

# =============================================================================
# SUBREDES — VPC de datos: solo privadas (Redshift nunca es publico)

resource "aws_subnet" "private_data" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.data.id
  cidr_block        = var.private_subnets_data[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.tags, { Name = "sbn-data-${count.index + 1}-${local.name_suffix}" })
}

# =============================================================================
# INTERNET GATEWAY — puerta de entrada/salida a Internet para la VPC principal
# Solo las subredes publicas lo usan (via route table).

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.principal.id

  tags = merge(local.tags, { Name = "igw-${local.name_suffix}" })
}

# =============================================================================
# ELASTIC IP para el NAT Gateway
# IP publica estatica que el NAT Gateway usa como origen de salida.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags, { Name = "eip-nat-${local.name_suffix}" })
}

# =============================================================================
# NAT GATEWAY — permite a las instancias PRIVADAS salir a Internet SIN ser accesibles desde fuera.
# Se crea en una subred PUBLICA (necesita rutar por el IGW para salir).

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_principal[0].id

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.tags, { Name = "nat-${local.name_suffix}" })
}

# =============================================================================
# TABLAS DE RUTEO

# --- Subredes publicas: rutan todo el trafico a Internet por el IGW -----------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, { Name = "rtb-pub-${local.name_suffix}" })
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public_principal[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Subredes privadas VPC principal: salen a Internet por el NAT Gateway ----
resource "aws_route_table" "private_principal" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  # Ruta hacia la VPC de datos via peering
  route {
    cidr_block                = var.vpc_data_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.principal_to_data.id
  }

  tags = merge(local.tags, { Name = "rtb-priv-${local.name_suffix}" })
}

resource "aws_route_table_association" "private_principal" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_principal[count.index].id
  route_table_id = aws_route_table.private_principal.id
}

# --- Subredes privadas VPC de datos: solo ruta de retorno hacia VPC principal -
resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.data.id

  route {
    cidr_block                = var.vpc_principal_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.principal_to_data.id
  }

  tags = merge(local.tags, { Name = "rtb-data-${local.name_suffix}" })
}

resource "aws_route_table_association" "private_data" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data.id
}

# =============================================================================
# VPC PEERING — conexion de red privada entre la VPC principal y la de datos

resource "aws_vpc_peering_connection" "principal_to_data" {
  vpc_id      = aws_vpc.principal.id
  peer_vpc_id = aws_vpc.data.id
  auto_accept = true

  tags = merge(local.tags, { Name = "peer-${local.name_suffix}" })
}

# =============================================================================
# SECURITY GROUPS — firewall a nivel de recurso, con estado (stateful)

# --- ALB: acepta HTTPS (443) y HTTP (80) desde Internet ----------------------
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
    description = "Salida hacia EC2 en cualquier puerto (target groups)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "sg-alb-${local.name_suffix}" })
}

# --- EC2: acepta trafico SOLO desde el SG del ALB ----------------------------
resource "aws_security_group" "ec2" {
  name_prefix        = "ec2-${local.name_suffix}"
  description = "Trafico entrante solo desde el ALB hacia las instancias EC2"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "Trafico de la app solo desde el ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Salida irrestricta (para NAT Gateway, Secrets Manager, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "sg-ec2-${local.name_suffix}" })
}

# --- Redis (ElastiCache): acepta SOLO desde el SG de EC2 ---------------------
resource "aws_security_group" "redis" {
  name_prefix        = "redis-${local.name_suffix}"
  description = "Puerto Redis (6379) solo accesible desde las instancias EC2"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "Redis desde EC2"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "sg-redis-${local.name_suffix}" })
}

# --- RDS (PostgreSQL): acepta SOLO desde el SG de EC2 ------------------------
resource "aws_security_group" "rds" {
  name_prefix        = "rds-${local.name_suffix}"
  description = "Puerto PostgreSQL (5432) solo accesible desde las instancias EC2"
  vpc_id      = aws_vpc.principal.id

  ingress {
    description     = "PostgreSQL desde EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "sg-rds-${local.name_suffix}" })
}

# --- Redshift: acepta SOLO desde el CIDR de la VPC principal (via peering) ---
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "sg-redshift-${local.name_suffix}" })
}

# --- VPC Endpoints Interface: acepta HTTPS desde las instancias privadas -----
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

# =============================================================================
# NETWORK ACLs — capa adicional de seguridad a nivel de subred (stateless)
# Complementan los Security Groups

# --- NACL subredes publicas (ALB) --------------------------------------------
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.principal.id
  subnet_ids = aws_subnet.public_principal[*].id

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

  # Puertos efimeros: respuestas TCP de retorno (1024-65535)
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

# --- NACL subredes privadas VPC principal (EC2/RDS/Redis) --------------------
resource "aws_network_acl" "private_principal" {
  vpc_id     = aws_vpc.principal.id
  subnet_ids = aws_subnet.private_principal[*].id

  # Trafico desde las subredes publicas (ALB -> EC2)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_principal_cidr
    from_port  = var.app_port
    to_port    = var.app_port
  }

  # Respuestas de retorno y trafico de salida (NAT, endpoints)
  ingress {
    rule_no    = 110
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

# --- NACL subredes privadas VPC de datos (Redshift) --------------------------
resource "aws_network_acl" "private_data" {
  vpc_id     = aws_vpc.data.id
  subnet_ids = aws_subnet.private_data[*].id

  # Solo permite el puerto de Redshift desde la VPC principal (via peering)
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
