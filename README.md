# EC2 + Wallarm Node + httpbin

Terraform project for deploying EC2 instances with Nginx reverse proxy, Wallarm WAF, and httpbin as a backend application.

## Architecture

```
Internet → Nginx (:80/:443) → [Wallarm WAF] → httpbin (:8000)
```

## What gets deployed

- **VPC** with public subnets, Internet Gateway, and Security Group
- **EC2 instances** (RHEL 9 or Ubuntu 24.04, selectable per instance)
- **Docker** with [httpbin](https://httpbin.org) container on port 8000
- **Nginx** as a reverse proxy to `127.0.0.1:8000`
- **Wallarm Node** (all-in-one installer) — WAF in front of httpbin
- **Route 53 A record** for the instance
- **Let's Encrypt certificate** via certbot with automatic renewal

## Quick start

```bash
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

## Variables

### Infrastructure

| Variable | Description | Default |
|---|---|---|
| `key_name` | AWS key pair name | — |
| `ssh_key_private` | Path to private SSH key | — |
| `region` | AWS region | `us-east-1` |
| `instance_name` | Resource name prefix | — |
| `security_group` | Security Group name | — |
| `instance_type` | EC2 instance type | `t3.small` |
| `ssd` | Root volume size in GB | `30` |
| `os` | Default OS: `rhel` or `ubuntu` | `rhel` |

### Instances

```hcl
instances = {
  "1" = { instance_type = "t3.small" }                   # uses global os
  "2" = { instance_type = "t3.medium", os = "ubuntu" }   # per-instance override
}
```

### Wallarm

| Variable | Description | Default |
|---|---|---|
| `wallarm_node_token` | Node token from Wallarm Console | `""` (skips installation) |
| `wallarm_version` | All-in-one installer version | `6.10.1` |
| `wallarm_cloud` | Cloud region: `US` or `EU` | `US` |
| `wallarm_labels` | Node group label | `group=default` |
| `wallarm_mode` | Filtering mode: `off`, `monitoring`, `safe_blocking`, `block` | `monitoring` |

### Domain and TLS

| Variable | Description | Default |
|---|---|---|
| `domain` | Instance FQDN (e.g. `host.example.com`) | `""` (skips DNS and TLS) |
| `route53_zone` | Route 53 hosted zone name | `""` |
| `certbot_email` | Email for Let's Encrypt notifications | `""` (registers without email) |

When `domain` is empty, only HTTP is configured — no DNS record or certificate is created.

## Initialization order (user_data)

1. Install Nginx
2. Install Docker, start httpbin container
3. Configure Nginx as reverse proxy
4. Install Wallarm Node (when `wallarm_node_token` is set)
5. Wait for DNS propagation, issue Let's Encrypt certificate (when `domain` is set)
6. Switch Nginx to HTTPS with HTTP → HTTPS 301 redirect

## Outputs

| Output | Description |
|---|---|
| `instance_ips` | Public IP addresses of all instances |
| `instance_os` | Effective OS for each instance |
