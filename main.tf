provider "aws" {
  region = var.region
}


data "aws_availability_zones" "available" {}

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat, Inc.

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.instance_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.instance_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.instance_name}-public-rt"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.instance_name}-public-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "security_group" {
  name   = var.security_group
  vpc_id = aws_vpc.main.id
  # Ingress: SSH only from 92.51.98.82/32
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["92.51.98.82/32"]
  }

  # Ingress: WireGuard
  ingress {
    description = "WireGuard"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: ESP (IP protocol 50)
  ingress {
    description = "ESP"
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: IPsec NAT-T
  ingress {
    description = "IPsec NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: IKE
  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress: HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress: allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# # Network Load Balancer 
# resource "aws_lb" "nlb" {
#   name               = "mbeschokov-nlb"  # Changed to nlb for clarity
#   internal           = false
#   load_balancer_type = "network"  # Type changed to network
#   subnets            = data.aws_subnets.default.ids
# }

# # Target Group for TCP traffic on port 80
# resource "aws_lb_target_group" "tg_80" {
#   name     = substr("mbeschokov-tg-80", 0, 32)
#   port     = 80
#   protocol = "TCP"
#   vpc_id   = data.aws_vpc.default.id
#   health_check {
#     protocol            = "TCP"
#     interval            = 30
#     timeout             = 10
#     healthy_threshold   = 3
#     unhealthy_threshold = 3
#   }
# }

# # Target Group for TCP traffic on port 443
# resource "aws_lb_target_group" "tg_443" {
#   name     = substr("mbeschokov-tg-443", 0, 32)
#   port     = 443
#   protocol = "TCP"
#   vpc_id   = data.aws_vpc.default.id
#   health_check {
#     protocol            = "TCP"
#     interval            = 30
#     timeout             = 10
#     healthy_threshold   = 3
#     unhealthy_threshold = 3
#   }
# }

# # Listener for port 80 (TCP)
# resource "aws_lb_listener" "tcp_80" {
#   load_balancer_arn = aws_lb.nlb.arn
#   port              = 80
#   protocol          = "TCP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.tg_80.arn
#   }
# }

# # Listener for port 443 (TCP)
# resource "aws_lb_listener" "tcp_443" {
#   load_balancer_arn = aws_lb.nlb.arn
#   port              = 443
#   protocol          = "TCP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.tg_443.arn
#   }
# }

resource "aws_instance" "main" {
  for_each               = var.instances
  ami                    = local.instance_ami[each.key]
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.security_group.id]
  subnet_id              = aws_subnet.public[index(local.instance_keys, each.key) % length(aws_subnet.public)].id
  user_data = templatefile("${path.module}/templatefiles/nginx_init.sh.tpl", {
    os                 = local.instance_os[each.key]
    wallarm_node_token = var.wallarm_node_token
    wallarm_version    = var.wallarm_version
    wallarm_major      = join(".", slice(split(".", var.wallarm_version), 0, 2))
    wallarm_cloud      = var.wallarm_cloud
    wallarm_labels     = var.wallarm_labels
    wallarm_mode       = var.wallarm_mode
    domain             = var.domain
    certbot_email      = var.certbot_email
  })
  tags = {
    Owner = var.key_name
    Name  = "${var.instance_name}-${each.key}"
  }
  root_block_device {
    volume_size = var.ssd
    # volume_type = var.ssdtype
    # throughput  = 600
    # iops        = 6000
  }
}

# DNS A record in Route 53
data "aws_route53_zone" "main" {
  count = var.domain != "" ? 1 : 0
  name  = var.route53_zone
}

resource "aws_route53_record" "main" {
  count   = var.domain != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain
  type    = "A"
  ttl     = 60
  records = [aws_instance.main[local.instance_keys[0]].public_ip]
}
