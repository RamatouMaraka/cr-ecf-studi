output "alb-dns-name_back" {
  value = aws_lb.application_lb_back.dns_name
}
output "elb-dns-name_front" {
  value = aws_lb.application_lb_front.dns_name
}