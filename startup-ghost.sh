#!/bin/sh

# @sacloud-desc-begin
# Ghostをセットアップします。
# http://docs.ghost.org/installation/deploy/ の手順にそっています。
# @sacloud-desc-end

# @sacloud-once

# Install dependencies
rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
rpm -ivh http://nginx.org/packages/centos/6/noarch/RPMS/nginx-release-centos-6-0.el6.ngx.noarch.rpm
yum install -y unzip nginx npm

## Install Supervisor
curl https://bitbucket.org/pypa/setuptools/raw/bootstrap/ez_setup.py | python
easy_install supervisor
curl https://raw.github.com/Supervisor/initscripts/master/redhat-init-mingalevme > /etc/init.d/supervisord
chmod +x /etc/init.d/supervisord

# Setup iptables
cp /etc/sysconfig/iptables /etc/sysconfig/iptables.orig
cat <<'EOT' > /etc/sysconfig/iptables
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [43:3272]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
EOT
service iptables restart

# Setup nginx
cp -r /etc/nginx/conf.d /etc/nginx/conf.d.orig
rm -f /etc/nginx/conf.d/*.conf
cat <<'EOT' > /etc/nginx/conf.d/ghost.conf
server {
    listen 80;
    server_name _;

    location / {
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   Host      $http_host;
        proxy_pass         http://127.0.0.1:2368;
    }
}
EOT
cat <<'EOT' > /etc/nginx/conf.d/gzip.conf
gzip on;
gzip_min_length 1000;
gzip_comp_level 5;
gzip_proxied any;
gzip_types text/css
           text/javascript
           text/xml
           text/plain
           application/javascript
           application/x-javascript
           application/json
           application/xml
           application/xhtml+xml
           application/rss+xml;
EOT
service nginx start
chkconfig nginx on

# Create ghost user
useradd -r -m -U ghost
export HOME=/home/ghost

# Setup Ghost
mkdir -p /var/www
cd /var/www
curl -L https://ghost.org/zip/ghost-latest.zip -o ghost.zip
unzip -uo ghost.zip -d ghost
cd ghost
npm install --production
chown -R ghost:ghost .

# Start Ghost on Supervisor
echo_supervisord_conf > /etc/supervisord.conf
mkdir -p /var/log/supervisor
cat <<'EOT' >> /etc/supervisord.conf
[program:ghost]
command = node index.js
directory = /var/www/ghost
user = ghost
autostart = true
autorestart = true
stdout_logfile = /var/log/supervisor/ghost.log
stderr_logfile = /var/log/supervisor/ghost_err.log
environment = NODE_ENV="production"
EOT
service supervisord start
chkconfig supervisord on

