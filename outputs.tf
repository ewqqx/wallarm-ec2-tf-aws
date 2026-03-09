output "instance_ips" {
  description = "Public IP addresses of all instances"
  value = {
    for k, instance in aws_instance.main :
    "${var.instance_name}-${k}" => instance.public_ip
  }
}

output "instance_os" {
  description = "Effective OS for each instance"
  value       = local.instance_os
}
