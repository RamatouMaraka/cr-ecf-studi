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
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 80
        to_port     = 80
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

# Creating key-pair on AWS using SSH-public key
resource "aws_key_pair" "deployer" {
  key_name   = var.key-name
  public_key = file("~/.ssh/id_rsa.pub")
}

// Backend servers
resource "aws_instance" "web_server_back" {
    ami             = "ami-04a92520784b93e73"
    instance_type   = "t2.micro"
    count           = 2
    security_groups = ["${aws_security_group.security_group.name}"]
    key_name        = aws_key_pair.deployer.key_name
    tags = {
        Name = "Back-${count.index + 1}"
        Environment = "demo"
        Role = "server"
    }
}
/*
resource "null_resource" "ansible" {
  provisioner "local-exec" {
    command = "ansible-playbook -i inventory.yml -u ubuntu playbooks.yml"
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [ 
    aws_instance.web_server_back
   ]
}
*/
// Frontend servers
resource "aws_instance" "web_server_front" {
    ami             = "ami-04a92520784b93e73"
    instance_type   = "t2.micro"
    count           = 2
    security_groups = ["${aws_security_group.security_group.name}"]
    // Script to install docker on the servers
    user_data = "${file("userdata.sh")}"
    key_name = aws_key_pair.deployer.key_name
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
//Frontend ALB
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
