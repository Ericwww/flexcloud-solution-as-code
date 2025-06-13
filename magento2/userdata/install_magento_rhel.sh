#!/bin/bash
# Variables
set -x
export ELB_IP=${1}
export DB_HOST=${2}
export DB_PASSWORD=${3}
export REDIS_HOST=${4}
export REDIS_PASSWORD=${5}
export ELASTICSEARCH_PASSWORD=${6}
export ELASTICSEARCH_HOST=${7}
export SFS_SHARED_PATH=${8}
export ADMIN_FIRSTNAME=${9}
export ADMIN_LASTNAME=${10}
export ADMIN_PASSWORD=${11}
export ADMIN_EMAIL=${12}
export MAGENTO_PUBLIC_KEY=${13}
export MAGENTO_PRIVATE_KEY=${14}
export IMAGE_NAME=${15}
export VAULT_ID=${16}
# export ENTERPRISE_PROJECT_ID=${17}
export WAIT_TIME=60

PROJECT_ID=$(curl http://169.254.169.254/openstack/latest/meta_data.json | grep -oP '"project_id": "\K[^"]+')
export PROJECT_ID
REGION=$(curl http://169.254.169.254/openstack/latest/meta_data.json | grep -oP '"region_id": "\K[^"]+')
export REGION
UUID=$(curl http://169.254.169.254/openstack/latest/meta_data.json | grep -oP '"uuid": "\K[^"]+')
export UUID

yum -y install jq
curl -sSL https://cn-north-4-hdn-koocli.obs.cn-north-4.myhuaweicloud.com/cli/latest/hcloud_install.sh -o ./hcloud_install.sh && bash ./hcloud_install.sh -y
hcloud configure set --cli-agree-privacy-statement=true

yum -y update
yum -y upgrade

# Install nginx
yum -y install nginx

# Install and configure php-fpm
# Install php
yum -y install epel-release yum-utils
yum -y install http://rpms.remirepo.net/enterprise/remi-release-8.rpm
yum-config-manager --enable remi-php81
yum -y install php
yum -y install php-bcmath
yum -y install php-ctype
yum -y install php-curl
yum -y install php-dom
yum -y install php-fileinfo
yum -y install php-filter
yum -y install php-gd
yum -y install php-hash
yum -y install php-iconv
yum -y install php-intl
yum -y install php-json
yum -y install php-libxml 
yum -y install php-mbstring
yum -y install php-openssl 
yum -y install php-pcre 
yum -y install php-pdo_mysql 
yum -y install php-simplexml 
yum -y install php-soap 
yum -y install php-sockets 
yum -y install php-sodium 
yum -y install php-tokenizer 
yum -y install php-xmlwriter 
yum -y install php-xsl 
yum -y install php-zip 
yum -y install php-zlib 
yum -y install php-lib-libxml
yum -y install php-fpm
yum -y install php-cli

# Modify php.ini
sed -i "s/.*cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php.ini
sed -i "s|.*date.timezone =|date.timezone = Asia/Shanghai|" /etc/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 2G/" /etc/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 1800/" /etc/php.ini
sed -i "s/zlib.output_compression = Off/zlib.output_compression = On/" /etc/php.ini
sed -i "s/.*realpath_cache_size.*/realpath_cache_size = 10M/" /etc/php.ini
sed -i "s/.*realpath_cache_ttl.*/realpath_cache_ttl = 7200/" /etc/php.ini
sed -i "s|;session.save_path = \"/tmp\"|session.save_path = /var/lib/php/session/|" /etc/php.ini

# Modify www.conf
sed -i "s/user = apache/user = nginx/" /etc/php-fpm.d/www.conf
sed -i "s/group = apache/group = nginx/" /etc/php-fpm.d/www.conf
sed -i "s|listen =.*|listen = /run/php-fpm/php-fpm.sock|" /etc/php-fpm.d/www.conf
sed -i "s|.*listen.owner =.*|listen.owner = nginx|" /etc/php-fpm.d/www.conf
sed -i "s/.*listen.group =.*/listen.group = nginx/" /etc/php-fpm.d/www.conf
sed -i "s/.*listen.mode.*/listen.mode = 0660/" /etc/php-fpm.d/www.conf
sed -i "s/.*env\[HOSTNAME\].*/env\[HOSTNAME\] = \$HOSTNAME/" /etc/php-fpm.d/www.conf
sed -i "s|.*env\[PATH\] = /usr/local/bin:/usr/bin:/bin|env\[PATH\] = /usr/local/bin:/usr/bin:/bin|" /etc/php-fpm.d/www.conf
sed -i "s|.*env\[TMP\] = /tmp|env\[TMP\] = /tmp|" /etc/php-fpm.d/www.conf
sed -i "s|.*env\[TMPDIR\] = /tmp|env\[TMPDIR\] = /tmp|" /etc/php-fpm.d/www.conf
sed -i "s|.*env\[TEMP\] = /tmp|env\[TEMP\] = /tmp|" /etc/php-fpm.d/www.conf

# Modify php-fpm.conf
cat>>/etc/php-fpm.conf<<EOF
[www]
listen = /run/php-fpm/php-fpm.sock
EOF

# Create directory for php session
mkdir -p /var/lib/php/session/
chown -R nginx:nginx /var/lib/php/
mkdir -p /run/php-fpm/
chown -R nginx:nginx /run/php-fpm/

# Create a new magento virtual host
cat>/etc/nginx/conf.d/magento.conf<<EOF
upstream fastcgi_backend {
    server  unix:/run/php-fpm/php-fpm.sock;
}
server {
    listen 80;
    server_name $ELB_IP;
    set \$MAGE_ROOT /usr/share/nginx/html/magento2;
    include /usr/share/nginx/html/magento2/nginx.conf.sample;
}
EOF

# Config SELinux and Firewald
yum -y install policycoreutils-python
semanage fcontext -a -t httpd_sys_rw_content_t '/usr/share/nginx/html/magento2/app/etc(/.*)?'
semanage fcontext -a -t httpd_sys_rw_content_t '/usr/share/nginx/html/magento2/var(/.*)?'
semanage fcontext -a -t httpd_sys_rw_content_t '/usr/share/nginx/html/magento2/pub/media(/.*)?'
semanage fcontext -a -t httpd_sys_rw_content_t '/usr/share/nginx/html/magento2/pub/static(/.*)?'
restorecon -Rv '/usr/share/nginx/html/magento2/'
yum -y install firewalld
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Install Composer
curl -sSL https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin/ --filename=composer
cat>>/etc/profile<<EOF
export COMPOSER_HOME=/usr/local/bin/
export PATH=\$COMPOSER_HOME:\$PATH
EOF
source /etc/profile

cat>/root/auth.json<<EOF
{
    "bitbucket-oauth": {},
    "github-oauth": {},
    "gitlab-oauth": {},
    "gitlab-token": {},
    "http-basic": {
        "repo.magento.com": {
            "username": "${MAGENTO_PUBLIC_KEY}",
            "password": "${MAGENTO_PRIVATE_KEY}"
        }
    },
    "bearer": {}
}
EOF

if [ -d "/root/.config/composer" ]; then
    mv /root/auth.json /root/.config/composer/
    cp /root/.config/composer/auth.json /usr/local/bin/auth.json
else
    mv /root/auth.json /usr/local/bin/
fi
composer -V

# Create a Composer project using the Magento
function create_magento_project() {
    if [ ! -d "/usr/share/nginx/html/magento2/" ]
    then
        mkdir -p /usr/share/nginx/html/magento2/
        composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.5 /usr/share/nginx/html/magento2/
    else
        rm -rf /usr/share/nginx/html/magento2/
        mkdir -p /usr/share/nginx/html/magento2/
        composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.5 /usr/share/nginx/html/magento2/
    fi
}
while true
do
    if create_magento_project
    then
        break
    else
        sleep ${WAIT_TIME}
    fi
done

cd /usr/share/nginx/html/magento2/ || exit
sudo find var generated vendor pub/static pub/media app/etc -type f -exec chmod g+w {} +
sudo find var generated vendor pub/static pub/media app/etc -type d -exec chmod g+ws {} +
sudo chown -R nginx:nginx .
sudo chmod u+x bin/magento

systemctl enable --now php-fpm
systemctl enable --now nginx

# Install Magento
sudo -u nginx php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento module:disable {Magento_Elasticsearch,Magento_Elasticsearch6,Magento_Elasticsearch7}

function install_magento(){
    sudo -u nginx php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento setup:install \
    --backend-frontname=admin \
    --admin-user=admin \
    --admin-password="${ADMIN_PASSWORD}" \
    --admin-firstname="${ADMIN_FIRSTNAME}" \
    --admin-lastname="${ADMIN_LASTNAME}" \
    --admin-email="${ADMIN_EMAIL}" \
    --base-url=http://"${ELB_IP}" \
    --db-host="${DB_HOST}" \
    --db-name=magento \
    --db-user=root \
    --db-password="${DB_PASSWORD}" \
    --cleanup-database \
    --language=en_US \
    --currency=USD \
    --timezone=America/Chicago \
    --use-rewrites=1 \
    --use-secure=0 \
    --session-save=redis \
    --session-save-redis-host="${REDIS_HOST}" \
    --session-save-redis-port=6379 \
    --session-save-redis-log-level=4 \
    --session-save-redis-db=2 \
    --session-save-redis-password="${REDIS_PASSWORD}" \
    --search-engine=elasticsearch7 \
    --elasticsearch-host="${ELASTICSEARCH_HOST}" \
    --elasticsearch-enable-auth=1 \
    --elasticsearch-username=elastic \
    --elasticsearch-password="${ELASTICSEARCH_PASSWORD}" \
    --elasticsearch-port=9200 \
    --elasticsearch-timeout=15
}

while true
do
    if install_magento
    then
        break
    else
        sleep ${WAIT_TIME}
    fi
done

# Magento sample data
wget -P /tmp/ https://documentation-samples.obs.cn-north-4.myhuaweicloud.com/solution-as-code-publicbucket/solution-as-code-moudle/e-commerce-shop-based-magento/v2/userdata/sampledata.sh

# Mount SFS shared directory
if [ ! -d "/mnt/sfs/magento2" ]
then
    yum -y install nfs-utils
    mkdir -p /mnt/sfs/magento2
    echo "${SFS_SHARED_PATH} /mnt/sfs/magento2 nfs vers=3,timeo=600,nolock 0 0" >> /etc/fstab
    mount -a
    df -h
    mkdir -p /mnt/sfs/magento2/app/etc
    mkdir -p /mnt/sfs/magento2/pub
    mv -u /usr/share/nginx/html/magento2/app/etc/env.php /mnt/sfs/magento2/app/etc/
    mv -u /usr/share/nginx/html/magento2/app/etc/config.php /mnt/sfs/magento2/app/etc/
    mv -u /usr/share/nginx/html/magento2/pub/static /mnt/sfs/magento2/pub/
    mv -u /usr/share/nginx/html/magento2/pub/media /mnt/sfs/magento2/pub/
    mv -u /usr/share/nginx/html/magento2/var /mnt/sfs/magento2/
fi

# Add a soft link for Magento
if [ ! -L "/usr/share/nginx/html/magento2/app/etc/env.php" ]
then
    cd /usr/share/nginx/html/magento2/app/etc || exit
    sudo -u nginx ln -s /mnt/sfs/magento2/app/etc/env.php .
fi

if [ ! -L "/usr/share/nginx/html/magento2/app/etc/config.php" ]
then
    cd /usr/share/nginx/html/magento2/app/etc || exit
    sudo -u nginx ln -s /mnt/sfs/magento2/app/etc/config.php .
fi

if [ ! -L "/usr/share/nginx/html/magento2/var" ]
then
    cd /usr/share/nginx/html/magento2/ || exit
    rm -rf ./var/ && sudo -u nginx ln -s /mnt/sfs/magento2/var .
fi

if [ ! -L "/usr/share/nginx/html/magento2/pub/static" ]
then
    cd /usr/share/nginx/html/magento2/pub || exit
    rm -rf ./static/ && sudo -u nginx ln -s /mnt/sfs/magento2/pub/static .
fi

if [ ! -L "/usr/share/nginx/html/magento2/pub/media" ]
then
    cd /usr/share/nginx/html/magento2/pub || exit
    rm -rf ./media/ && sudo -u nginx ln -s /mnt/sfs/magento2/pub/media .
fi

cp -a /usr/local/bin/auth.json /usr/share/nginx/html/magento2
# Turn off two factor authentication
sudo -u nginx php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento module:disable Magento_TwoFactorAuth
sudo -u nginx php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento setup:di:compile
sudo -u nginx php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento cache:flush
sudo -u nginx php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento cron:install
sudo -u nginx php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento cron:run --group index

sudo chown -R nginx:nginx /usr/share/nginx/html/magento2/

# Adjust maximum number of child processes
avi_mem=$(free -m | awk '/Mem:/ {print $2}')
avi_mem_num=$(echo "$avi_mem" | grep -oE '[0-9]+(\.[0-9]+)?')
max_children=$(echo "scale=0; $avi_mem_num/40" | bc)
sed -i "s|pm.max_children = 50|pm.max_children = ${max_children}|" /etc/php-fpm.d/www.conf
systemctl restart php-fpm
until systemctl is-active php-fpm
do
    sleep 3
done

# Package image
hcloud IMS CreateWholeImage --cli-region="${REGION}" --enterprise_project_id="${ENTERPRISE_PROJECT_ID}" \
--instance_id="${UUID}" --name="${IMAGE_NAME}" --vault_id="${VAULT_ID}"
