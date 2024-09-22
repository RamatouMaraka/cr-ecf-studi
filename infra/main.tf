provider "aws" {
  profile = "default"
  region = "eu-west-3" 
}

data "aws_vpc" "default" { 
  default = true
} 

data "aws_subnets" "subnet_ids" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "security_group" {
    name        = "web-server"
    description = "Allow incoming HTTP Connections"
    
    ingress {
        from_port   = 80
        to_port     = 80 
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
     
    ingress {
        from_port   = 3000
        to_port     = 3000
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

// Backend servers
resource "aws_instance" "web_server_back" {
    ami             = "ami-0cdfcb9783eb43c45"
    instance_type   = "t2.micro"
    count           = 2
    security_groups = ["${aws_security_group.security_group.name}"]
    user_data = <<-EOF
       #!/bin/bash
       sudo su
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "<html><h1> Welcome to studi. this is backend virtual machine from $(hostname -f)...</p> </h1></html>" >> /var/www/html/index.html
    EOF
    tags = {
        Name = "Back-${count.index + 1}"
    }
}
// Frontend servers
resource "aws_instance" "web_server_front" {
    ami             = "ami-0cdfcb9783eb43c45"
    instance_type   = "t2.micro"
    count           = 2
    security_groups = ["${aws_security_group.security_group.name}"]
    user_data = <<-EOF
       #!/bin/bash
       sudo su
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "<html><h1> Welcome to studi. this is frontend virtual machine from $(hostname -f)...</p> </h1></html>" >> /var/www/html/index.html
    EOF
    tags = {
        Name = "Front-${count.index + 1}"
    }
}

//Backend ALB
resource "aws_lb" "application_lb_back" {
    name            = "alb-back"
    internal        = false
    ip_address_type     = "ipv4"
    load_balancer_type = "application"
    security_groups = [aws_security_group.security_group.id]
    subnets            = data.aws_subnets.subnet_ids.ids
    tags = {
        Name = "alb-back"
    }
}
//Frontend  ALB
resource "aws_lb" "application_lb_front" {
    name            = "alb-front"
    internal        = false
    ip_address_type     = "ipv4"
    load_balancer_type = "application"
    security_groups = [aws_security_group.security_group.id]
    subnets            = data.aws_subnets.subnet_ids.ids
    tags = {
        Name = "alb-front"
    }
}

// Backend Target group
resource "aws_lb_target_group" "target_group_back" {
    health_check {
        interval            = 10
        path                = "/"
        protocol            = "HTTP"
        timeout             = 5
        healthy_threshold   = 5
        unhealthy_threshold = 2
    }
    name          = "tg-back"
    port          = 80
    protocol      = "HTTP"
    target_type   = "instance"
    vpc_id = data.aws_vpc.default.id
}
// Frontend Target group
resource "aws_lb_target_group" "target_group_front" {
    health_check {
        interval            = 10
        path                = "/"
        protocol            = "HTTP"
        timeout             = 5
        healthy_threshold   = 5
        unhealthy_threshold = 2
    }
    name          = "tg-front"
    port          = 80
    protocol      = "HTTP"
    target_type   = "instance"
    vpc_id = data.aws_vpc.default.id
}

// Backend listenier
resource "aws_lb_listener" "alb-listener_back" {
    load_balancer_arn          = aws_lb.application_lb_back.arn
    port                       = 80
    protocol                   = "HTTP"
    default_action {
        target_group_arn         = aws_lb_target_group.target_group_back.arn
        type                     = "forward"
    }
}
// Frontend listenier
resource "aws_lb_listener" "alb-listener_front" {
    load_balancer_arn          = aws_lb.application_lb_front.arn
    port                       = 80
    protocol                   = "HTTP"
    default_action {
        target_group_arn         = aws_lb_target_group.target_group_front.arn
        type                     = "forward"
    }
}

// Backend Attach servers to target group
resource "aws_lb_target_group_attachment" "ec2_attach_back" {
    count = length(aws_instance.web_server_back)
    target_group_arn = aws_lb_target_group.target_group_back.arn
    target_id        = aws_instance.web_server_back[count.index].id
}
// Frontend Attach servers to target group
resource "aws_lb_target_group_attachment" "ec2_attach_front" {
    count = length(aws_instance.web_server_front)
    target_group_arn = aws_lb_target_group.target_group_front.arn
    target_id        = aws_instance.web_server_front[count.index].id
}