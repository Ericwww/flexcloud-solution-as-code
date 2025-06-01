#!/bin/bash
set -x
sleep 60

#安装JDK11
wget -P /usr/local https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/jdk-11.0.21_linux-x64_bin.tar.gz
tar -xvf /usr/local/jdk-11.0.21_linux-x64_bin.tar.gz -C /usr/local
cat>>/etc/profile<<EOF
export JAVA_HOME=/usr/local/jdk-11.0.21
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
source /etc/profile
java -version

cat >> /etc/security/limits.conf << EOF
elk soft nofile 65535
elk hard nofile 65535
elk soft nproc 4096
elk hard nproc 4096
EOF
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -p

while true; do
if [ -f "/usr/local/elasticsearch-7.9.3-linux-x86_64.tar.gz" ];then
echo "File exists"
break
else
echo "File does not exists"
sleep 10
fi
done

#安装ES
mkdir /usr/local/es
tar -xvf /usr/local/elasticsearch-7.9.3-linux-x86_64.tar.gz -C /usr/local/es
sed -i "36s/UseConcMarkSweepGC/UseG1GC/" /usr/local/es/elasticsearch-7.9.3/config/jvm.options
wget -P /usr/local/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/elasticsearch-analysis-ik-7.9.3.tar.gz
mkdir /usr/local/es/elasticsearch-7.9.3/plugins/ik
tar -xvf /usr/local/elasticsearch-analysis-ik-7.9.3.tar.gz -C /usr/local/es/elasticsearch-7.9.3/plugins/ik/
mkdir /usr/local/es/elasticsearch-7.9.3/data

ip_str=""
while true; do
if [ -f "/tmp/ip.txt" ];then
ip_str=`cat /tmp/ip.txt`
break
else
echo "File does not exists"
sleep 10
fi
done
slave_ip=$(ifconfig | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1 | grep -v '127.0.0.1')
sed -i "s/#cluster.name:.*$/cluster.name: es/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s/#node.name:.*$/node.name: node-$1/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s|#path.data:.*$|path.data: /usr/local/es/elasticsearch-7.9.3/data|" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s|#path.logs:.*$|path.logs: /usr/local/es/elasticsearch-7.9.3/logs|" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s/#network.host:.*$/network.host: ${slave_ip}/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s|#transport.tcp.port:.*$|transport.tcp.port: 9300|" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i "s/#discovery.seed_hosts:.*$/discovery.seed_hosts: \[$ip_str\]/" /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
sed -i 's/#cluster.initial_master_nodes:.*$/cluster.initial_master_nodes: \["node-1"\]/' /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml
cat >> /usr/local/es/elasticsearch-7.9.3/config/elasticsearch.yml << EOF
node.master: true
node.data: true
discovery.zen.ping_timeout: 60s
http.cors.enabled: true
http.cors.allow-origin: "*"
http.cors.allow-headers: Authorization
http.cors.allow-credentials: true
xpack.monitoring.collection.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.enabled: true
xpack.license.self_generated.type: basic
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: /usr/local/es/elasticsearch-7.9.3/config/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: /usr/local/es/elasticsearch-7.9.3/config/elastic-certificates.p12
EOF

count=1
while [ $count -le 10 ];do
if [ -f "/tmp/elastic-certificates.p12" ];then
mv /tmp/elastic-certificates.p12 /usr/local/es/elasticsearch-7.9.3/config/
echo "File exists"
break
else
echo "File does not exists"
sleep 10
fi
count=$((count+1))
done
chmod 744 /usr/local/es/elasticsearch-7.9.3/config/elastic-certificates.p12
groupadd es
useradd es -g es
chown -Rf es:es /usr/local/es/

wget -P /etc/systemd/system/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/elasticsearch.service
chmod +x /etc/systemd/system/elasticsearch.service

systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch