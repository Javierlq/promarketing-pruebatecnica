# =============================================================================
# IAM — rol e instance profile para las EC2 del Auto Scaling Group

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "role-ec2-${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = merge(local.tags, { Name = "role-ec2-${local.name_suffix}" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_app" {
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_secret.arn]
  }

  statement {
    sid       = "DecryptWithKms"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.s3.arn]
  }

  statement {
    sid = "WriteAppLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/casino/*"]
  }
}

resource "aws_iam_role_policy" "ec2_app" {
  name   = "policy-ec2-${local.name_suffix}"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_app.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "profile-ec2-${local.name_suffix}"
  role = aws_iam_role.ec2.name
}

# =============================================================================
# APPLICATION LOAD BALANCER + enrutamiento por path

resource "aws_lb" "main" {
  name               = "alb-${local.name_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public_principal : s.id]

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = merge(local.tags, { Name = "alb-${local.name_suffix}" })
}

resource "aws_lb_target_group" "app" {
  for_each = local.servicios_infra

  name        = "tg-${each.key}-${var.proyecto}-${var.num}"
  port        = each.value.port
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

  tags = merge(local.tags, { Name = "tg-${each.key}-${local.name_suffix}" })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.enable_acm_validation ? aws_acm_certificate_validation.alb[0].certificate_arn : aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["frontsite"].arn
  }
}

resource "aws_lb_listener_rule" "routing" {
  for_each = { for k, v in local.servicios_infra : k => v if k != "frontsite" }

  listener_arn = aws_lb_listener.https.arn
  priority     = 100 + index(keys(local.servicios_infra), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}

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
# COMPUTO — Launch Templates y Auto Scaling Groups por microservicio

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

resource "aws_launch_template" "app" {
  for_each = local.servicios_infra

  name_prefix   = "lt-${each.key}-${local.name_suffix}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.ec2_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    security_groups = [aws_security_group.ec2.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "Iniciando ${each.key} en el puerto ${each.value.port}"
  EOF
  )

  tags = merge(local.tags, {
    Name = "lt-${each.key}-${local.name_suffix}"
  })
}

resource "aws_autoscaling_group" "app" {
  for_each = local.servicios_infra

  name                = "asg-${each.key}-${local.name_suffix}"
  vpc_zone_identifier = local.private_subnet_ids
  
  target_group_arns   = [aws_lb_target_group.app[each.key].arn]
  
  # ELB health checks para que reemplace instancias si fallan en el Load Balancer
  health_check_type         = "ELB"
  health_check_grace_period = 300

  # Configuracion de Alta Disponibilidad (HA)
  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.app[each.key].id
    version = "$Latest"
  }


  dynamic "tag" {
    for_each = merge(local.tags, {
      Name = "ec2-${each.key}-${local.name_suffix}-asg"
      App  = each.key
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# =============================================================================
# RDS — base de datos transaccional (OLTP), Multi-AZ

resource "aws_db_subnet_group" "main" {
  name        = "dbsg-${local.name_suffix}"
  subnet_ids  = [for s in aws_subnet.private_principal : s.id]
  description = "Subnet group para RDS transaccional"

  tags = merge(local.tags, { Name = "dbsg-${local.name_suffix}" })
}

resource "aws_db_instance" "main" {
  identifier                = "rds-${local.name_suffix}"
  engine                    = var.rds_engine
  engine_version            = var.rds_engine_version
  instance_class            = var.rds_instance_class
  allocated_storage         = 20
  storage_type              = "gp3"
  storage_encrypted         = true
  db_name                   = "casino_db"
  username                  = var.db_username
  password                  = random_password.db_pass.result
  db_subnet_group_name      = aws_db_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  multi_az                  = true
  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "rds-${local.name_suffix}-final"

  tags = merge(local.tags, { Name = "rds-${local.name_suffix}" })
}

# =============================================================================
# REDSHIFT SERVERLESS — bodega de datos historica (OLAP) en la VPC de datos

resource "aws_redshiftserverless_namespace" "data" {
  namespace_name      = "ns-${local.name_suffix}"
  admin_username      = var.db_username
  admin_user_password = random_password.db_pass.result
  db_name             = "casino_dw"

  tags = merge(local.tags, { Name = "ns-${local.name_suffix}" })
}

resource "aws_redshiftserverless_workgroup" "data" {
  workgroup_name      = "wg-${local.name_suffix}"
  namespace_name      = aws_redshiftserverless_namespace.data.namespace_name
  base_capacity       = var.redshift_base_capacity
  subnet_ids          = [for s in aws_subnet.private_data : s.id]
  security_group_ids  = [aws_security_group.redshift.id]
  publicly_accessible = false

  tags = merge(local.tags, { Name = "wg-${local.name_suffix}" })
}

# =============================================================================
# ELASTICACHE REDIS — capa de cache con failover automatico Multi-AZ

resource "aws_elasticache_subnet_group" "redis" {
  name        = "ecsg-${local.name_suffix}"
  subnet_ids  = [for s in aws_subnet.private_principal : s.id]
  description = "Subnet group para ElastiCache Redis"

  tags = merge(local.tags, { Name = "ecsg-${local.name_suffix}" })
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "redis-${local.name_suffix}"
  description                = "Cache Redis para el casino online"
  node_type                  = var.redis_node_type
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = merge(local.tags, { Name = "redis-${local.name_suffix}" })
}