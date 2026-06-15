# instances.tf
# Computo y datos: ALB + listeners, 4 EC2, RDS transaccional, Redshift
# (bodega historica) y ElastiCache Redis.


# =============================================================================
# AMI — Amazon Linux 2023 (ultima version en la region)

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# APPLICATION LOAD BALANCER (ALB)

resource "aws_lb" "main" {
  name               = "alb-${local.name_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public_principal[*].id

  # Activa los access logs del ALB hacia el bucket de logs (s3.tf)
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = merge(local.tags, { Name = "alb-${local.name_suffix}" })
}

# --- Target Group: define como el ALB envia trafico a las EC2 ----------------
resource "aws_lb_target_group" "app" {
  name        = "tg-app-${local.name_suffix}"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.principal.id
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(local.tags, { Name = "tg-app-${local.name_suffix}" })
}

# --- Listener HTTPS (443): termina TLS con el certificado ACM ----------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --- Listener HTTP (80): redirige todo el trafico a HTTPS --------------------
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# =============================================================================
# INSTANCIAS EC2 — los 4 microservicios del casino
# Se crean con for_each sobre la lista de apps para no repetir codigo.

resource "aws_instance" "app" {
  for_each = toset(var.apps)

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.private_principal[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # Sin clave SSH publica: en produccion se accede via SSM Session Manager.
  # Esto evita exponer el puerto 22 a Internet.

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "ec2-${each.key}-${local.name_suffix}"
    App  = each.key
  })
}

# --- Registrar cada EC2 en el target group del ALB ---------------------------
resource "aws_lb_target_group_attachment" "app" {
  for_each = aws_instance.app

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = each.value.id
  port             = var.app_port
}

# =============================================================================
# RDS — base de datos transaccional (OLTP) en la VPC principal
# Multi-AZ: AWS mantiene una replica en otra AZ para failover automatico.

resource "aws_db_subnet_group" "main" {
  name        = "dbsg-${local.name_suffix}"
  subnet_ids  = aws_subnet.private_principal[*].id
  description = "Subnet group para RDS transaccional"

  tags = merge(local.tags, { Name = "dbsg-${local.name_suffix}" })
}

resource "aws_db_instance" "main" {
  identifier             = "rds-${local.name_suffix}"
  engine                 = var.rds_engine
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = "casino_db"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = true
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = merge(local.tags, { Name = "rds-${local.name_suffix}" })
}

# =============================================================================
# REDSHIFT — bodega de datos historica (OLAP) en la VPC secundaria

resource "aws_redshift_subnet_group" "data" {
  name        = "rssg-${local.name_suffix}"
  subnet_ids  = aws_subnet.private_data[*].id
  description = "Subnet group para Redshift"

  tags = merge(local.tags, { Name = "rssg-${local.name_suffix}" })
}

resource "aws_redshift_cluster" "data" {
  cluster_identifier        = "rs-${local.name_suffix}"
  database_name             = "casino_dw"
  master_username           = var.db_username
  master_password           = var.db_password
  node_type                 = var.redshift_node_type
  cluster_type              = "single-node"
  cluster_subnet_group_name = aws_redshift_subnet_group.data.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]
  publicly_accessible       = false
  encrypted                 = true
  skip_final_snapshot       = true

  tags = merge(local.tags, { Name = "rs-${local.name_suffix}" })
}

# =============================================================================
# ELASTICACHE REDIS — capa de cache para reducir latencia en la app
# Replication group = Redis con un nodo primario y posibilidad de replicas.
# =============================================================================

resource "aws_elasticache_subnet_group" "redis" {
  name        = "ecsg-${local.name_suffix}"
  subnet_ids  = aws_subnet.private_principal[*].id
  description = "Subnet group para ElastiCache Redis"

  tags = merge(local.tags, { Name = "ecsg-${local.name_suffix}" })
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "redis-${local.name_suffix}"
  description          = "Cache Redis para el casino online"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = merge(local.tags, { Name = "redis-${local.name_suffix}" })
}
