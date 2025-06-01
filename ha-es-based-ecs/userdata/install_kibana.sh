#!/bin/bash
set -x
apt-get update
apt-get -y install expect
kibana_ip=$(ifconfig | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1 | grep -v '127.0.0.1')
wget -P /usr/local/ https://artifacts.elastic.co/downloads/kibana/kibana-7.9.3-linux-x86_64.tar.gz
tar -xvf /usr/local/kibana-7.9.3-linux-x86_64.tar.gz -C /usr/local/

IFS=',' read -ra parts <<<"$4"
# 创建一个新的空数组，用于收集分发的slave-ip数组
slave_ips_list=()
ip_str='"'
ip_str+="http://${2}"
ip_str+=':9200"'
for part in "${parts[@]}"; do
  slave_ips_list+=("$part")
  ip_str+=', "'
  ip_str+="http://$part"
  ip_str+=':9200"'
done
echo "${ip_str[@]}"

sed -i "s/#server.port:.*$/server.port: 5601/" /usr/local/kibana-7.9.3-linux-x86_64/config/kibana.yml
sed -i "s/#server.host:.*$/server.host: $kibana_ip/" /usr/local/kibana-7.9.3-linux-x86_64/config/kibana.yml
sed -i "s|#elasticsearch.hosts:.*$|elasticsearch.hosts: \[$ip_str\]|" /usr/local/kibana-7.9.3-linux-x86_64/config/kibana.yml
sed -i "s/#elasticsearch.requestTimeout:.*$/elasticsearch.requestTimeout: 90000/" /usr/local/kibana-7.9.3-linux-x86_64/config/kibana.yml
sed -i "s/#i18n.locale:.*$/i18n.locale: zh-CN/" /usr/local/kibana-7.9.3-linux-x86_64/config/kibana.yml
cat >>/usr/local/kibana-7.9.3-linux-x86_64/config/kibana.yml <<EOF
xpack.reporting.capture.browser.chromium.disableSandbox: true
xpack.security.encryptionKey: "asdfghjkloiuytrewqfghnjmklhjkhgj"
xpack.reporting.encryptionKey: "asdfghjkloiuytrewqfghnjmklhjkhgj"
xpack.encryptedSavedObjects.encryptionKey: "asdfghjkloiuytrewqfghnjmklhjkhgj"
EOF

/usr/local/kibana-7.9.3-linux-x86_64/bin/kibana-keystore --allow-root create
/usr/bin/expect <<EOF
spawn /usr/local/kibana-7.9.3-linux-x86_64/bin/kibana-keystore --allow-root add elasticsearch.username
expect "Enter value for elasticsearch.username:"
send "kibana_system\r"
expect eof
EOF

/usr/bin/expect <<EOF
spawn /usr/local/kibana-7.9.3-linux-x86_64/bin/kibana-keystore --allow-root add elasticsearch.password
expect "Enter value for elasticsearch.password:"
send "$1\r"
expect eof
EOF

while true; do
    status=$(curl -u elastic:$1 -X GET "$2:9200/_cluster/health?pretty" | grep "status" | cut -d ":" -f 2 | cut -d "," -f 1)
    nodes_status=$(curl -u elastic:$1 -X GET "$2:9200/_cluster/health?pretty" | grep "number_of_nodes" | cut -d ":" -f 2 | cut -d "," -f 1)
    echo "check status $status ...$nodes_status"
    if [ $status == '"green"' ] && [ $nodes_status = "$3" ]; then
      echo "check ok! quit..."
      break
    else
      echo "wait 10s..."
      sleep 10s
    fi
  done

apt-get -y install fonts-ipafont-gothic
apt-get -y install xfonts-base
apt-get -y install xfonts-cyrillic
apt-get -y install xfonts-100dpi
apt-get -y install xfonts-75dpi
apt-get -y install xorg



/usr/local/kibana-7.9.3-linux-x86_64/bin/kibana --allow-root
