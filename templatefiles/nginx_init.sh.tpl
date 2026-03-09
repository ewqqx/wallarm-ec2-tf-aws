#!/bin/bash
set -e

# Install nginx
%{ if os == "ubuntu" ~}
apt-get update -y
apt-get install -y nginx
%{ else ~}
dnf -y update
dnf -y install nginx
%{ endif ~}

# Install Docker
%{ if os == "ubuntu" ~}
apt-get install -y docker.io
%{ else ~}
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io
%{ endif ~}
systemctl enable --now docker

# Run httpbin on port 8000
docker run -d --name httpbin --restart always -p 8000:80 kennethreitz/httpbin

# Remove default site configs that conflict with default_server
%{ if os == "ubuntu" ~}
rm -f /etc/nginx/sites-enabled/default
%{ else ~}
sed -i '/listen.*80.*default_server/d' /etc/nginx/nginx.conf
%{ endif ~}

# Initial HTTP nginx config
cat > /etc/nginx/conf.d/httpbin.conf <<'NGINX'
server {
    listen 80 default_server;
%{ if domain != "" ~}
    server_name ${domain};
%{ endif ~}
%{ if wallarm_node_token != "" ~}
    wallarm_mode ${wallarm_mode};
%{ endif ~}

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX

systemctl restart nginx

%{ if wallarm_node_token != "" ~}
# Install Wallarm node (all-in-one)
curl -O https://meganode.wallarm.com/${wallarm_major}/wallarm-${wallarm_version}.x86_64-glibc.sh
sudo env WALLARM_LABELS='${wallarm_labels}' sh wallarm-${wallarm_version}.x86_64-glibc.sh -- --batch -t ${wallarm_node_token} -c ${wallarm_cloud}
systemctl restart nginx
%{ endif ~}

%{ if domain != "" ~}
# Install certbot
%{ if os == "ubuntu" ~}
apt-get install -y certbot
%{ else ~}
dnf -y install certbot
%{ endif ~}

# Wait for DNS to resolve to this instance's public IP
MY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
for i in $(seq 1 30); do
  RESOLVED=$(dig +short ${domain} @8.8.8.8 2>/dev/null)
  if [ "$RESOLVED" = "$MY_IP" ]; then
    break
  fi
  sleep 5
done

# Get Let's Encrypt certificate (standalone: stop nginx, get cert, start nginx)
systemctl stop nginx
certbot certonly --standalone -d ${domain} \
  --non-interactive --agree-tos \
  %{ if certbot_email != "" ~}
  -m ${certbot_email} \
  %{ else ~}
  --register-unsafely-without-email \
  %{ endif ~}

# Write final HTTPS nginx config
cat > /etc/nginx/conf.d/httpbin.conf <<'NGINX'
server {
    listen 80 default_server;
    server_name ${domain};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    server_name ${domain};

    ssl_certificate     /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;

%{ if wallarm_node_token != "" ~}
    wallarm_mode ${wallarm_mode};
%{ endif ~}

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX

systemctl start nginx

# Auto-renewal cron
echo "0 3 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew
%{ endif ~}
