#!bin/bash
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
export USE_SAMPLE_DATA=${15}
export PHP_VERSION="8.1"

magento2conf="upstream fastcgi_backend {
  server  unix:/run/php/php$PHP_VERSION-fpm.sock;
}

server {
  listen 80;
  server_name $ELB_IP;
  set \$MAGE_ROOT /var/www/html/magento;
  include /var/www/html/magento/nginx.conf.sample;
}"

sudo apt-get update

# Setup NGINX
sudo apt install nginx -y
sed -i 's/listen \[::\]:80 default_server;$/# &/g' /etc/nginx/sites-available/default
sudo systemctl start nginx
sudo systemctl enable nginx
sudo apt install unzip -y

# Setup PHP
sudo apt install -y software-properties-common 
yes | sudo add-apt-repository ppa:ondrej/php
sudo apt-get install php$PHP_VERSION php$PHP_VERSION-dev php$PHP_VERSION-fpm php$PHP_VERSION-bcmath php$PHP_VERSION-intl php$PHP_VERSION-soap php$PHP_VERSION-zip php$PHP_VERSION-curl php$PHP_VERSION-mbstring php$PHP_VERSION-mysql php$PHP_VERSION-gd php$PHP_VERSION-xml --no-install-recommends  -y
php -v

# Configure PHP
sudo sed -i 's/^\(max_execution_time = \)[0-9]*/\17200/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/^\(max_input_time = \)[0-9]*/\17200/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/^\(memory_limit = \)[0-9]*M/\12048M/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/^\(post_max_size = \)[0-9]*M/\164M/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/^\(upload_max_filesize = \)[0-9]*M/\164M/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/expose_php = On/expose_php = Off/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/;realpath_cache_size = 16k/realpath_cache_size = 512k/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/;realpath_cache_ttl = 120/realpath_cache_ttl = 86400/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/short_open_tag = Off/short_open_tag = On/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/;max_input_vars = 1000/max_input_vars = 50000/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/session.gc_maxlifetime = 1440/session.gc_maxlifetime = 28800/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/mysql.allow_persistent = On/mysql.allow_persistent = Off/' /etc/php/$PHP_VERSION/fpm/php.ini 
sudo sed -i 's/mysqli.allow_persistent = On/mysqli.allow_persistent = Off/' /etc/php/$PHP_VERSION/fpm/php.ini

# Configure Opcache
sudo bash -c "cat > /etc/php/$PHP_VERSION/fpm/conf.d/10-opcache.ini <<END
zend_extension=opcache.so
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 356
opcache.interned_strings_buffer = 4
opcache.max_accelerated_files = 100000
opcache.max_wasted_percentage = 15
opcache.use_cwd = 1
opcache.validate_timestamps = 0
;opcache.revalidate_freq = 2
;opcache.validate_permission= 1
;opcache.validate_root= 1
opcache.file_update_protection = 2
opcache.revalidate_path = 0
opcache.save_comments = 1
opcache.load_comments = 1
opcache.fast_shutdown = 1
opcache.enable_file_override = 0
opcache.optimization_level = 0xffffffff
opcache.inherited_hack = 1
opcache.max_file_size = 0
opcache.consistency_checks = 0
opcache.force_restart_timeout = 60
opcache.log_verbosity_level = 1
opcache.protect_memory = 0
END"

sudo systemctl start php$PHP_VERSION-fpm.service
sudo systemctl enable php$PHP_VERSION-fpm.service
sudo systemctl status php$PHP_VERSION-fpm.service --no-pager
sudo systemctl restart php$PHP_VERSION-fpm.service


#Setup Composer
curl -sS https://getcomposer.org/installer -o composer-setup.php
sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
export COMPOSER_ALLOW_SUPERUSER=1
export COMPOSER_HOME="$HOME/.config/composer";
composer -V

sudo mkdir /var/www/html/magento
sudo chmod -R 755 /var/www/html/magento/

composer config --global http-basic.repo.magento.com ${MAGENTO_PUBLIC_KEY} ${MAGENTO_PRIVATE_KEY}
composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.5 /var/www/html/magento

cd /var/www/html/magento/

php -d memory_limit=-1 bin/magento setup:install \
    --backend-frontname=admin \
    --admin-user=admin \
    --admin-password="${ADMIN_PASSWORD}" \
    --admin-firstname="${ADMIN_FIRSTNAME}" \
    --admin-lastname="${ADMIN_LASTNAME}" \
    --admin-email="${ADMIN_EMAIL}" \
    --base-url=http://$ELB_IP \
    --db-host="${DB_HOST}" \
    --db-name=magento \
    --db-user=root \
    --db-password="${DB_PASSWORD}" \
    --cleanup-database \
    --language=en_US \
    --currency=USD \
    --use-rewrites=1 \
    --use-secure=0 \
    --search-engine=elasticsearch7 \
    --elasticsearch-host="${ELASTICSEARCH_HOST}" \
    --elasticsearch-enable-auth=1 \
    --elasticsearch-username=elastic \
    --elasticsearch-password="${ELASTICSEARCH_PASSWORD}" \
    --elasticsearch-port=9200 \
    --elasticsearch-timeout=15

yes | php -d memory_limit=-1 bin/magento setup:config:set \
    --cache-backend=redis \
    --cache-backend-redis-server="${REDIS_HOST}" \
    --cache-backend-redis-port=6379 \
    --cache-backend-redis-db=0 \
    --cache-backend-redis-password="${REDIS_PASSWORD}"

yes | php -d memory_limit=-1 bin/magento setup:config:set \
    --page-cache=redis \
    --page-cache-redis-server="${REDIS_HOST}" \
    --page-cache-redis-port=6379 \
    --page-cache-redis-db=1 \
    --page-cache-redis-password="${REDIS_PASSWORD}"

yes | php -d memory_limit=-1 bin/magento setup:config:set \
    --session-save=redis \
    --session-save-redis-host="${REDIS_HOST}" \
    --session-save-redis-port=6379 \
    --session-save-redis-log-level=4 \
    --session-save-redis-db=2 \
    --session-save-redis-password="${REDIS_PASSWORD}"

php -d memory_limit=-1 bin/magento module:disable Magento_AdminAdobeImsTwoFactorAuth
php -d memory_limit=-1 bin/magento module:disable Magento_TwoFactorAuth
php -d memory_limit=-1 bin/magento setup:di:compile
php -d memory_limit=-1 bin/magento cron:run --group index
php -d memory_limit=-1 bin/magento maintenance:disable

if [[ ${USE_SAMPLE_DATA} == true ]]; then
    echo "going to install sampledata"
    php -d memory_limit=-1 bin/magento deploy:mode:set developer
    php -d memory_limit=-1 bin/magento sampledata:deploy
    php -d memory_limit=-1 bin/magento setup:upgrade
    php -d memory_limit=-1 bin/magento deploy:mode:set production
fi

sudo bash -c "echo '$magento2conf' > /etc/nginx/conf.d/magento.conf"
sudo nginx -t
sudo systemctl restart nginx

sudo chmod -R 777 /var/www/html/magento/*

sudo chown -R www-data:www-data /var/www/html/magento
sudo find var generated vendor pub/static pub/media app/etc -type f -exec chmod g+w {} +

curl http://$ELB_IP

tail -n 20 /var/log/nginx/error.log 
