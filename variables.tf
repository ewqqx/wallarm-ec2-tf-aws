variable "key_name" {
  description = "AWS key pair name"
}
variable "ssh_key_private" {
  description = "Path to private SSH key file"
}

variable "region" {
  default = "us-east-1"
}
variable "vpc_cidr" {
  default = "10.10.0.0/16"
}
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.2.0/24"]
}
variable "security_group" {
  description = "Security group name"
}
variable "instance_type" {
  default = "t3.small"
}
variable "ssd" {
  default = "30"
}
# variable "ssdtype" {
#   default = "gp3"
# }
variable "instance_name" {
  description = "Prefix for instance and resource names"
}
variable "os" {
  description = "Operating system to use. Allowed values: rhel, ubuntu"
  type        = string
  default     = "rhel"
  # default   = "ubuntu"

  validation {
    condition     = contains(["rhel", "ubuntu"], var.os)
    error_message = "Allowed values for os are: rhel, ubuntu."
  }
}

variable "instances" {
  type = map(object({
    instance_type = string
    os            = optional(string, "") # "rhel" | "ubuntu" | "" (falls back to var.os)
  }))
  default = {
    "1" = { instance_type = "t3.small", os = "" }
  }
}

variable "wallarm_node_token" {
  description = "Wallarm node token for registration"
  type        = string
  sensitive   = true
  default     = ""
}

variable "wallarm_version" {
  description = "Wallarm all-in-one installer version (e.g. 6.10.1)"
  type        = string
  default     = "6.10.1"
}

variable "wallarm_cloud" {
  description = "Wallarm cloud region: US or EU"
  type        = string
  default     = "US"

  validation {
    condition     = contains(["US", "EU"], var.wallarm_cloud)
    error_message = "Allowed values for wallarm_cloud are: US, EU."
  }
}

variable "wallarm_labels" {
  description = "Wallarm node group label"
  type        = string
  default     = "group=default"
}

variable "wallarm_mode" {
  description = "Wallarm filtering mode: off, monitoring, safe_blocking, block"
  type        = string
  default     = "monitoring"

  validation {
    condition     = contains(["off", "monitoring", "safe_blocking", "block"], var.wallarm_mode)
    error_message = "Allowed values: off, monitoring, safe_blocking, block."
  }
}

variable "domain" {
  description = "FQDN for the instance (e.g. mbeschokov.wallarm-cloud.com). Empty to skip DNS/TLS."
  type        = string
  default     = ""
}

variable "certbot_email" {
  description = "Email for Let's Encrypt certificate registration"
  type        = string
  default     = ""
}

variable "route53_zone" {
  description = "Route 53 hosted zone domain name (e.g. wallarm-cloud.com)"
  type        = string
  default     = ""
}

locals {
  instance_keys = sort(keys(var.instances))

  # Per-instance effective OS: use instance-level os if set, otherwise fall back to global var.os
  instance_os = {
    for k, v in var.instances :
    k => coalesce(v.os, var.os)
  }

  # Per-instance AMI
  instance_ami = {
    for k, os in local.instance_os :
    k => os == "ubuntu" ? data.aws_ami.ubuntu.id : data.aws_ami.rhel9.id
  }

  # Per-instance SSH user
  instance_user = {
    for k, os in local.instance_os :
    k => os == "ubuntu" ? "ubuntu" : "ec2-user"
  }
}



