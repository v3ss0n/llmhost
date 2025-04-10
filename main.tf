provider "aws" {
  region = "us-east-1"  # Change to your preferred region
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "llm-vpc"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "llm-igw"
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "llm-public-subnet"
  }
}

# Create a route table for the public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "llm-public-route-table"
  }
}

# Associate the public subnet with the route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create a security group for LiteLLM Gateway
resource "aws_security_group" "litellm_gateway" {
  name        = "litellm-gateway-sg"
  description = "Allow traffic to LiteLLM Gateway"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
    Name = "litellm-gateway-sg"
  }
}

# Create a security group for TGI Instances
resource "aws_security_group" "tgi_instances" {
  name        = "tgi-instances-sg"
  description = "Allow traffic to TGI Instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 8080
    to_port     = 8080
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
    Name = "tgi-instances-sg"
  }
}

# Create an Elastic Load Balancer
resource "aws_lb" "main" {
  name               = "llm-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.litellm_gateway.id]
  subnets            = [aws_subnet.public.id]

  tags = {
    Name = "llm-load-balancer"
  }
}

# Create a target group for the TGI instances
resource "aws_lb_target_group" "tgi_instances" {
  name     = "llm-tgi-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "llm-tgi-target-group"
  }
}

# Register TGI instances with the target group
resource "aws_lb_target_group_attachment" "tgi_instances" {
  count            = length(aws_instance.tgi_instances)
  target_group_arn = aws_lb_target_group.tgi_instances.arn
  target_id        = aws_instance.tgi_instances[count.index].id
  port             = 8080
}

# Create a listener for the load balancer
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tgi_instances.arn
  }

  tags = {
    Name = "llm-load-balancer-http-listener"
  }
}

# Launch LiteLLM Gateway EC2 instance
resource "aws_instance" "litellm_gateway" {
  ami           = "ami-04b4f1a9cf54c11d0"  # Change to a valid AMI ID for your region
  instance_type = "t3.large"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.litellm_gateway.name]

  tags = {
    Name = "litellm-gateway"
  }
}

# Launch TGI Instances EC2 instances
resource "aws_instance" "tgi_instances" {
  count         = 2  # Change to the number of TGI instances you need
  ami           = "ami-04b4f1a9cf54c11d0"  # Change to a valid AMI ID for your region
  instance_type = "g5.12xlarge"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.tgi_instances.name]

  tags = {
    Name = "tgi-instance-${count.index + 1}"
  }
}

# Create a security group for Elasticsearch
resource "aws_security_group" "elasticsearch" {
  name        = "elasticsearch-sg"
  description = "Allow traffic to Elasticsearch"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 9200
    to_port     = 9200
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
    Name = "elasticsearch-sg"
  }
}

# Create a security group for Kibana
resource "aws_security_group" "kibana" {
  name        = "kibana-sg"
  description = "Allow traffic to Kibana"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5601
    to_port     = 5601
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
    Name = "kibana-sg"
  }
}

# Launch Elasticsearch EC2 instance
resource "aws_instance" "elasticsearch" {
  ami           = "ami-04b4f1a9cf54c11d0"  # Change to a valid AMI ID for your region
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.elasticsearch.name]

  tags = {
    Name = "elasticsearch"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y openjdk-11-jdk
              wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
              sudo sh -c 'echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list'
              sudo apt-get update
              sudo apt-get install -y elasticsearch
              sudo systemctl enable elasticsearch
              sudo systemctl start elasticsearch
              EOF
}

# Launch Kibana EC2 instance
resource "aws_instance" "kibana" {
  ami           = "ami-04b4f1a9cf54c11d0"  # Change to a valid AMI ID for your region
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.kibana.name]

  tags = {
    Name = "kibana"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y openjdk-11-jdk
              wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
              sudo sh -c 'echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list'
              sudo apt-get update
              sudo apt-get install -y kibana
              sudo sed -i "s/#server.host: \"localhost\"/server.host: \"0.0.0.0\"/" /etc/kibana/kibana.yml
              sudo sed -i "s/#elasticsearch.hosts: \[\"http:\/\/localhost:9200\"\]/elasticsearch.hosts: \[\"http:\/\/${aws_instance.elasticsearch.private_ip}:9200\"\]/" /etc/kibana/kibana.yml
              sudo systemctl enable kibana
              sudo systemctl start kibana
              EOF
}
