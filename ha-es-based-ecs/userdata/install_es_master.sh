#!/bin/bash
set -x
apt-get update
apt-get -y install expect

#安装JDK11
wget -P /usr/local https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/jdk-11.0.21_linux-x64_bin.tar.gz
tar -xvf /usr/local/jdk-11.0.21_linux-x64_bin.tar.gz -C /usr/local
cat >>/etc/profile <<EOF
export JAVA_HOME=/usr/local/jdk-11.0.21
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
source /etc/profile
java -version

cat >>/etc/security/limits.conf <<EOF
elk soft nofile 65535
elk hard nofile 65535
elk soft nproc 4096
elk hard nproc 4096
EOF
echo "vm.max_map_count=262144" >>/etc/sysctl.conf
sysctl -p

# 获取服务器的ip
IFS=',' read -ra parts <<<"$2"
slave_ips_list=()
ip_str='"'
master_ip=$(ifconfig | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1 | grep -v '127.0.0.1')
ip_str+="${master_ip}"
ip_str+=':9300"'
for part in "${parts[@]}"; do
  slave_ips_list+=("$part")
  ip_str+=', "'
  ip_str+="$part"
  ip_str+=':9300"'
done
servers_ip=("${master_ip}" "${slave_ips_list[@]}")

for each_ip in "${slave_ips_list[@]}"; do
  echo "start check $each_ip ..."
  while true; do
    status=$(curl --http0.9 -v $each_ip:22)
    echo "check status $each_ip:$status ..."
    if [[ $status =~ SSH ]]; then
      echo "check ok! quit..."
      break
    else
      echo "wait 20s..."
      sleep 20s
    fi
  done
done

if [ $2 != "" ]; then
  echo $ip_str >/tmp/ip.txt
for ip in "${slave_ips_list[@]}"; do
/usr/bin/expect <<EOF
spawn scp -r /tmp/ip.txt root@$ip:/tmp/
expect "Are you sure you want to continue connecting (yes/no)?"
send "yes\r"
expect "*password:"
send "$1\r"
expect eof
EOF
done
fi

#安装ES
mkdir /usr/local/es
wget -P /usr/local/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/elasticsearch-7.9.3-linux-x86_64.tar.gz
tar -xvf /usr/local/elasticsearch-7.9.3-linux-x86_64.tar.gz -C /usr/local/es
sed -i "36s/UseConcMarkSweepGC/UseG1GC/" /usr/local/es/elasticsearch-7.9.3/config/jvm.options

#安装ik分词
wget -P /usr/local/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/elasticsearch-analysis-ik-7.9.3.tar.gz
mkdir /usr/local/es/elasticsearch-7.9.3/plugins/ik
tar -xvf /usr/local/elasticsearch-analysis-ik-7.9.3.tar.gz -C /usr/local/es/elasticsearch-7.9.3/plugins/ik/
mkdir /usr/local/es/elasticsearch-7.9.3/data

for ip in "${parts[@]}"; do
  /usr/bin/expect <<EOF
spawn scp /usr/local/elasticsearch-7.9.3-linux-x86_64.tar.gz /usr/local/elasticsearch-analysis-ik-7.9.3.zip root@$ip:/usr/local
expect root*:
send "$1\r"
expect eof
EOF
done

#修改ES配置文件
sed -i "s/#cluster.name:.*$/cluster.name: es/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s/#node.name:.*$/node.name: node-1/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s|#path.data:.*$|path.data: /usr/local/es/elasticsearch-7.9.3/data|" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s|#path.logs:.*$|path.logs: /usr/local/es/elasticsearch-7.9.3/logs|" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s/#network.host:.*$/network.host: $master_ip/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s|#transport.tcp.port:.*$|transport.tcp.port: 9300|" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s/#discovery.seed_hosts:.*$/discovery.seed_hosts: \[$ip_str\]/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i 's/#cluster.initial_master_nodes:.*$/cluster.initial_master_nodes: \["node-1"\]/' /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
cat >>/usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml <<EOF
discovery.zen.ping_timeout: 60s
http.cors.enabled: true
http.cors.allow-origin: "*"
http.cors.allow-headers: Authorization
http.cors.allow-credentials: true
xpack.monitoring.collection.enabled: true

xpack.security.enabled: true
xpack.license.self_generated.type: basic
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: /usr/local/es/elasticsearch-7.9.3/config/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: /usr/local/es/elasticsearch-7.9.3/config/elastic-certificates.p12
EOF

#配置x-pack认证
/usr/local/es/elasticsearch-7.9.3/bin/elasticsearch-certutil cert -out config/elastic-certificates.p12 -pass ""
chmod 744 /usr/local/es/elasticsearch-7.9.3/config/elastic-certificates.p12
for ip in "${parts[@]}"; do
/usr/bin/expect <<EOF
spawn scp /usr/local/es/elasticsearch-7.9.3/config/elastic-certificates.p12 root@$ip:/tmp/
expect root*:
send "$1\r"
expect eof
EOF
done

#创建普通用户
groupadd es
useradd es -g es
chown -Rf es:es /usr/local/es/

wget -P /etc/systemd/system/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/elasticsearch.service
chmod +x /etc/systemd/system/elasticsearch.service

systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch



#监测服务启动状态
for each_ip in "${servers_ip[@]}"; do
  while true; do
    nc -zv $each_ip 9200 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "Port 9200 is up"
      break
    else
      echo "Port 9200 is down, sleeping for 10 seconds"
      sleep 10
    fi
  done
done

#配置各组件密码
/usr/bin/expect <<EOF
spawn /usr/local/es/elasticsearch-7.9.3/bin/elasticsearch-setup-passwords interactive
expect "Please confirm that you would like to continue*"
send "y\r"
expect "Enter password for \[elastic\]: "
send "$1\r"
expect "Reenter password for \[elastic\]"
send "$1\r"
expect "Enter password for \[apm_system\]"
send "$1\r"
expect "Reenter password for \[apm_system\]"
send "$1\r"
expect "Enter password for \[kibana_system\]"
send "$1\r"
expect "Reenter password for \[kibana_system\]"
send "$1\r"
expect "Enter password for \[logstash_system\]"
send "$1\r"
expect "Reenter password for \[logstash_system\]"
send "$1\r"
expect "Enter password for \[beats_system\]"
send "$1\r"
expect "Reenter password for \[beats_system\]"
send "$1\r"
expect "Enter password for \[remote_monitoring_user\]"
send "$1\r"
expect "Reenter password for \[remote_monitoring_user\]"
send "$1\r"
expect eof
EOF
