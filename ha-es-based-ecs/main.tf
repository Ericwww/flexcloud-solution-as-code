terraform {
  required_providers {
    huaweicloud = {
      source = "huaweicloud/huaweicloud"
    }
  }
}

provider "huaweicloud" {
  cloud      = "apistack.one.hu"
  region     = "eu-central-6001"
  insecure   = true
  auth_url   = "https://iam-pub.eu-central-6001.apistack.one.hu/v3"
}

locals {
  slave_ecs = [join(",", huaweicloud_compute_instance.elasticserach[*].access_ip_v4)]
}

data "huaweicloud_images_image" "image" {
  most_recent = true
  name        = "Ubuntu 20.04 server 64bit"
  visibility  = "public"
}

resource "huaweicloud_vpc" "vpc" {
  name = var.vpc_name
  cidr = "172.16.0.0/16"
}

resource "huaweicloud_vpc_subnet" "subnet" {
  name       = "${var.vpc_name}-subnet"
  cidr       = "172.16.1.0/24"
  gateway_ip = "172.16.1.1"
  vpc_id     = huaweicloud_vpc.vpc.id
}

resource "huaweicloud_networking_secgroup" "secgroup" {
  name = var.security_group_name
}

resource "huaweicloud_compute_servergroup" "servergroup-es" {
  name     = "${var.ecs_name}-es"
  policies = ["anti-affinity"]
}

resource "huaweicloud_networking_secgroup_rule" "allow_ping" {
  description       = "Allows accesses to websites over HTTP."
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "172.16.0.0/16"
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
}

resource "huaweicloud_networking_secgroup_rule" "allow_ssh_linux" {
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = 22
  port_range_max    = 22
  protocol          = "tcp"
  remote_ip_prefix  = "172.16.0.0/16"
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
}

resource "huaweicloud_networking_secgroup_rule" "es" {
  description       = "Allows accesses to websites over HTTP."
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = 9200
  port_range_max    = 9200
  protocol          = "tcp"
  remote_ip_prefix  = "172.16.0.0/16"
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
}

resource "huaweicloud_networking_secgroup_rule" "kibana" {
  description       = "Allows accesses to websites over HTTP."
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = 5601
  port_range_max    = 5601
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
}

resource "huaweicloud_vpc_eip" "myeip" {
  count = 2

  bandwidth {
    charge_mode = "bandwidth"
    name        = "${var.ecs_name}_eip"
    share_type  = "PER"
    size        = 100
  }

  publicip {
    type = "5_bgp"
  }
}

resource "huaweicloud_compute_instance" "es-master" {
  depends_on = [local.slave_ecs]

  name               = "${var.ecs_name}-master"
  image_id           = data.huaweicloud_images_image.image.id
  flavor_id          = "s6.xlarge.2"
  security_group_ids = [huaweicloud_networking_secgroup.secgroup.id]
  system_disk_size   = 40
  system_disk_type   = "SSD"
  admin_pass         = var.ecs_password
  network {
    uuid = huaweicloud_vpc_subnet.subnet.id
  }
  scheduler_hints {
    group = huaweicloud_compute_servergroup.servergroup-es.id
  }

  eip_id    = huaweicloud_vpc_eip.myeip[0].id
  user_data = "#!/bin/bash\necho 'root:${var.ecs_password}'|chpasswd\nwget -P /root/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/install_es_master.sh\nchmod 700 /root/install_es_master.sh\nsource /root/install_es_master.sh ${var.ecs_password} ${local.slave_ecs[0]} > /tmp/install_elasticsearch_master.log 2>&1\nrm -rf /root/install_es_master.sh"
  #   agent_list = "hss,ces"
}

resource "huaweicloud_compute_instance" "elasticserach" {
  count = var.es_ecs_count - 1

  name               = "${var.ecs_name}-es${count.index + 1}"
  image_id           = data.huaweicloud_images_image.image.id
  flavor_id          = "s6.xlarge.2"
  security_group_ids = [huaweicloud_networking_secgroup.secgroup.id]
  system_disk_size   = 40
  system_disk_type   = "SSD"
  admin_pass         = var.ecs_password
  network {
    uuid = huaweicloud_vpc_subnet.subnet.id
  }
  scheduler_hints {
    group = huaweicloud_compute_servergroup.servergroup-es.id
  }

  user_data = "#!/bin/bash\necho 'root:${var.ecs_password}'|chpasswd\nwget -P /root/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/install_es_slave.sh\nchmod 700 /root/install_es_slave.sh\nsource /root/install_es_slave.sh ${count.index + 2} > /tmp/install_elasticsearch_slave.log 2>&1\nrm -rf /root/install_es_slave.sh"
  #   agent_list = "hss,ces"
}

resource "huaweicloud_compute_instance" "kibana" {
  depends_on = [huaweicloud_compute_instance.es-master, local.slave_ecs]

  name               = "${var.ecs_name}-kibana"
  image_id           = data.huaweicloud_images_image.image.id
  flavor_id          = "s6.large.2"
  security_group_ids = [huaweicloud_networking_secgroup.secgroup.id]
  system_disk_size   = 40
  system_disk_type   = "SSD"
  admin_pass         = var.ecs_password
  network {
    uuid = huaweicloud_vpc_subnet.subnet.id
  }
  scheduler_hints {
    group = huaweicloud_compute_servergroup.servergroup-es.id
  }

  eip_id    = huaweicloud_vpc_eip.myeip[1].id
  user_data = "#!/bin/bash\necho 'root:${var.ecs_password}'|chpasswd\nwget -P /root/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/ha-es-based-ecs/install_kibana.sh\nchmod 700 /root/install_kibana.sh\nsource /root/install_kibana.sh ${var.ecs_password} ${huaweicloud_compute_instance.es-master.access_ip_v4} ${var.es_ecs_count} ${local.slave_ecs[0]} > /tmp/install_kibana.log 2>&1\nrm -rf /root/install_kibana.sh"
  #   agent_list = "hss,ces"
}

output "kibana_address" {
  value = "http://${huaweicloud_vpc_eip.myeip[1].address}:5601"
}

output "es_address" {
  value = "Elasticsearch后台服务IP地址：${huaweicloud_compute_instance.es-master.access_ip_v4} ${join(" ", huaweicloud_compute_instance.elasticserach[*].access_ip_v4)}。请在浏览器输入：http://任意一个IP地址:9200，即可访问Elasticsearch。"
}