provider "aws" {
  region = "us-east-2"
}

locals {
  full_db_endpoint = aws_db_instance.wordpress-db.endpoint
}

resource "aws_vpc" "wordpress-vpc" {
  cidr_block = "10.10.0.0/16"

  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "web-subnet-1" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "web-subnet-1"
  }
}

resource "aws_subnet" "web-subnet-2" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "web-subnet-2"
  }
}

resource "aws_subnet" "web-subnet-3" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = "us-east-2c"

  tags = {
    Name = "web-subnet-3"
  }
}

resource "aws_subnet" "db-subnet-1" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "db-subnet-1"
  }
}

resource "aws_subnet" "db-subnet-2" {
  vpc_id            = aws_vpc.wordpress-vpc.id
  cidr_block        = "10.10.5.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name = "db-subnet-1"
  }
}

resource "aws_internet_gateway" "wordpress-igw" {
  vpc_id = aws_vpc.wordpress-vpc.id

  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "wordpress-rt" {
  vpc_id = aws_vpc.wordpress-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress-igw.id
  }

  tags = {
    Name = "wordpress-rt"
  }
}

resource "aws_route_table_association" "web-subnet-association1" {
  subnet_id      = aws_subnet.web-subnet-1.id
  route_table_id = aws_route_table.wordpress-rt.id
}

resource "aws_route_table_association" "web-subnet-association2" {
  subnet_id      = aws_subnet.web-subnet-2.id
  route_table_id = aws_route_table.wordpress-rt.id
}

resource "aws_route_table_association" "web-subnet-association3" {
  subnet_id      = aws_subnet.web-subnet-3.id
  route_table_id = aws_route_table.wordpress-rt.id
}

resource "aws_security_group" "wordpress-sg" {
  name        = "Wordpress Security Group"
  description = "Allows SSH,HTTP/S"
  vpc_id      = aws_vpc.wordpress-vpc.id

  ingress {
    description = "SSH_Inbound"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["Removed for security"]
  }

  ingress {
    description = "HTTP_Inbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS_Inbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Wordpress Security Group"
  }
}

resource "aws_security_group" "ec2-rds" {
  name        = "wp-ec2-rds"
  description = "ec2 to rds"
  vpc_id      = aws_vpc.wordpress-vpc.id
}

resource "aws_security_group_rule" "ec2-rds-rule" {
  type                     = "egress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds-ec2.id
  security_group_id        = aws_security_group.ec2-rds.id
}


resource "aws_security_group" "rds-ec2" {
  name        = "wp-rds-ec2"
  description = "rds to ec2"
  vpc_id      = aws_vpc.wordpress-vpc.id
}

resource "aws_security_group_rule" "rds-ec2-rule" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ec2-rds.id
  security_group_id        = aws_security_group.rds-ec2.id
}


resource "aws_lb" "wordpress-lb" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress-sg.id, aws_security_group.ec2-rds.id, aws_security_group.rds-ec2.id]
  subnets            = [aws_subnet.web-subnet-1.id, aws_subnet.web-subnet-2.id, aws_subnet.web-subnet-3.id]
}

resource "aws_lb_target_group" "wordpress-tg" {
  name     = "wordpress-lb-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.wordpress-vpc.id
}

resource "aws_lb_listener" "https-listener" {
  load_balancer_arn = aws_lb.wordpress-lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "Removed for security"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress-tg.arn
  }
}

resource "aws_launch_template" "wordpress-launch_temp" {
  name = "wordpress-launch-temp"

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 30
    }
  }

  image_id               = "ami-027e10ce74628f4e5"
  instance_type          = "t2.micro"
  key_name               = "linux-vm"
  vpc_security_group_ids = [aws_security_group.wordpress-sg.id, aws_security_group.ec2-rds.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Define the new database hostname
    DB_HOSTNAME=${local.db_hostname}

    # Update the wp-config.php file with the new hostname
    sudo sed -i "s/define( 'DB_HOST', '[^']*' );/define( 'DB_HOST', '$DB_HOSTNAME' );/" /var/www/techselftaught/wordpress/wp-config.php
    sudo systemctl restart nginx
  EOF
  )

  depends_on = [aws_db_instance.wordpress-db]
}

resource "aws_autoscaling_group" "wordpress-asg" {
  vpc_zone_identifier = [aws_subnet.web-subnet-1.id, aws_subnet.web-subnet-2.id, aws_subnet.web-subnet-3.id]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 3
  target_group_arns   = [aws_lb_target_group.wordpress-tg.arn]

  launch_template {
    id      = aws_launch_template.wordpress-launch_temp.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_policy" "wordpress-asg-scaling-policy" {
  name                   = "wordpress-asg-scaling-policy"
  autoscaling_group_name = aws_autoscaling_group.wordpress-asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60.0
  }
}

resource "aws_db_subnet_group" "wordpress-rds-subgroup" {
  name       = "wordpress-rds-subgroup"
  subnet_ids = [aws_subnet.db-subnet-1.id, aws_subnet.db-subnet-2.id]
}

resource "aws_db_instance" "wordpress-db" {
  allocated_storage           = 20
  db_name                     = "wordpress_terraform"
  engine                      = "mysql"
  engine_version              = "8.0.33"
  instance_class              = "db.t3.micro"
  skip_final_snapshot         = true
  username                    = "admin"
  manage_master_user_password = true
  apply_immediately           = true
  db_subnet_group_name        = "wordpress-rds-subgroup"
  vpc_security_group_ids      = [aws_security_group.rds-ec2.id]
  snapshot_identifier         = "wordpress-snapshot"

  depends_on = [aws_db_subnet_group.wordpress-rds-subgroup]
}

locals {
  db_hostname = split(":", local.full_db_endpoint)[0]
}

output "db_endpoint" {
  value = aws_db_instance.wordpress-db.endpoint
}

output "lb-dns" {
  value = aws_lb.wordpress-lb.dns_name
}

import {
  to = aws_route53_zone.wordpress-zone
  id = "Z0069374127K3XARICGA1"
}

resource "aws_route53_zone" "wordpress-zone" {
  name = "techselftaught.com"
}

resource "aws_route53_record" "root-a" {
  zone_id = aws_route53_zone.wordpress-zone.zone_id
  name    = "techselftaught.com"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress-lb.dns_name
    zone_id                = aws_lb.wordpress-lb.zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_lb.wordpress-lb]
}
