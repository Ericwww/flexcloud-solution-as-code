#!/bin/bash
echo "Please choose to deploy or remove sample data. For installation, please enter \"deploy\". For deletion, please enter \"remove\":"
echo "Please enter your selection:"
read -r choice
case $choice in
    deploy) echo "Start installing sample data"
        sudo -u www-data php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento deploy:mode:set developer
        sudo -u www-data php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento sampledata:deploy
        sudo -u www-data php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento setup:upgrade
        echo "Sample data installation completed"
    ;;
    remove) echo "Start deleting sample data"
        sudo -u www-data php -d memory_limit=-1 /usr/share/nginx/html/magento2/bin/magento sampledata:remove
        echo "Sample data deleted successfully"
    ;;
esac