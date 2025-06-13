terraform {
  required_providers {
    huaweicloud = {
      source = "huaweicloud/huaweicloud"
      version = "1.73.9"
    }
  }
}

provider "huaweicloud" {
  cloud      = "apistack.one.hu"
  region     = "eu-central-6001"
  insecure   = true
  auth_url   = "https://iam-pub.eu-central-6001.apistack.one.hu/v3"
  endpoints = {
    iam = "https://iam-pub.eu-central-6001.apistack.one.hu"
  }
}

locals {
  vpc_id    = length(var.vpc_id) > 0 ? var.vpc_id : huaweicloud_vpc.vpc[0].id
  subnet_id = length(var.subnet_id) > 0 ? var.subnet_id : huaweicloud_vpc_subnet.subnet[0].id
}

resource "huaweicloud_vpc" "vpc" {
    count = length(var.vpc_id) > 0 ? 0 : 1
  name = var.vpc_name
  cidr = "192.168.0.0/16"
}

resource "huaweicloud_vpc_subnet" "subnet" {
    count = length(var.subnet_id) > 0 ? 0 : 1
  name       = var.vpc_name
  cidr       = "192.168.1.0/24"
  gateway_ip = "192.168.1.1"
  vpc_id     = local.vpc_id
}

resource "huaweicloud_networking_secgroup" "secgroup" {
  name = var.security_group_name
}

resource "huaweicloud_networking_secgroup_rule" "allow_ping" {
  description       = "Allows accesses to websites over HTTP."
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
}

resource "huaweicloud_networking_secgroup_rule" "allow_frontend" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
    port_range_min             = 80
  port_range_max = 80
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
}

resource "huaweicloud_networking_secgroup_rule" "allow_elb_accessing_ecs" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "100.125.0.0/16"
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
}

resource "huaweicloud_vpc_eip" "eip_ecs" {
  count = var.ecs_number
  name  = "${var.vpc_name}-ecs"
  bandwidth {
    name        = "${var.vpc_name}-ecs"
    share_type  = "PER"
    size        = "300"
    charge_mode = "traffic"
  }
  publicip {
    type = "5_bgp"
  }
}

resource "huaweicloud_vpc_eip" "eip_elb" {
  name = "${var.vpc_name}-elb"
  bandwidth {
    name        = "${var.vpc_name}-elb"
    share_type  = "PER"
    size        = var.eip_bandwidth_size
    charge_mode = "bandwidth"
  }
  publicip {
    type = "5_bgp"
  }
}

resource "huaweicloud_compute_servergroup" "servergroup" {
  name     = "${var.ecs_name}-servergroup"
  policies = ["anti-affinity"]
}

# resource "huaweicloud_rds_instance" "rds_instance" {
#   name                = var.rds_name
#   flavor              = data.huaweicloud_rds_flavors.rds_flavor.flavors[0].name
#   ha_replication_mode = "async"
#   vpc_id              = local.vpc_id
#   subnet_id           = local.subnet_id
#   security_group_id   = huaweicloud_networking_secgroup.secgroup.id
#   availability_zone = [
#     data.huaweicloud_availability_zones.az.names[0],
#     data.huaweicloud_availability_zones.az.names[0],
#   ]
#   db {
#     password = var.rds_password
#     type     = "MySQL"
#     version  = "8.0"
#   }
#   volume {
#     type = "ULTRAHIGH"
#     size = var.rds_volume_size
#   }
#   backup_strategy {
#     keep_days  = 7
#     start_time = "02:00-03:00"
#   }
# }

# resource "huaweicloud_rds_database" "database" {
#   instance_id   = huaweicloud_rds_instance.rds_instance.id
#   name          = "magento"
#   character_set = "utf8mb4"
# }

resource "huaweicloud_dcs_instance" "redis_instance" {
  name             = var.redis_name
  engine           = "Redis"
  engine_version   = "6.0"
  capacity         = var.redis_capacity
  flavor           = data.huaweicloud_dcs_flavors.dcs_flavors.flavors[0].name
  password         = var.redis_password
  vpc_id           = local.vpc_id
  subnet_id        = local.subnet_id
  whitelist_enable = false
  availability_zones = [
    data.huaweicloud_availability_zones.az.names[0]
  ]
  backup_policy {
    backup_type = "auto"
    save_days   = 3
    backup_at   = [1, 3, 5, 7]
    begin_at    = "02:00-04:00"
  }
}

resource "huaweicloud_identity_agency" "identity_agency" {
  delegated_service_name = "op_svc_ecs"
  name                   = var.ecs_name
  duration               = "ONEDAY"
  project_role {
    project = "eu-central-6001"
    roles = ["ECS FullAccess", "IMS FullAccess", "VPC Administrator", "VPC Administrator", "Server Administrator", "DNS Administrator"]
  }

}

resource "huaweicloud_cbr_vault" "cbr_vault" {
  name            = var.cbr_vault_name
  type            = "server"
  protection_type = "backup"
  size            = 100
}

resource "huaweicloud_sfs_turbo" "sfs_turbo" {
  name              = var.sfs_turbo_name
  size              = var.sfs_turbo_size
  share_type        = "STANDARD"
  enhanced          = false
  vpc_id            = local.vpc_id
  subnet_id         = local.subnet_id
  security_group_id = huaweicloud_networking_secgroup.secgroup.id
  availability_zone = data.huaweicloud_availability_zones.az.names[0]
}

resource "huaweicloud_compute_instance" "magento1" {
  # depends_on = [elasticsearch]
  name                        = "${var.ecs_name}-1"
  image_id                    = data.huaweicloud_images_image.rhel.id
  flavor_id                   = "s6.xlarge.2"
  security_group_ids          = [huaweicloud_networking_secgroup.secgroup.id]
  system_disk_type            = "SSD"
  system_disk_size            = 40
  admin_pass                  = var.ecs_password
  delete_disks_on_termination = true
  network {
    uuid = local.subnet_id
  }
  scheduler_hints {
    group = huaweicloud_compute_servergroup.servergroup.id
  }
  agency_name = huaweicloud_identity_agency.identity_agency.name
  # agent_list = "hss,ces"
  eip_id    = huaweicloud_vpc_eip.eip_ecs[0].id
#   user_data = "#!/bin/bash\necho 'root:${var.ecs_password}' | chpasswd\nwget -P /tmp/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/magento2-base-ecs/install_magento.sh\nchmod +x /tmp/install_magento.sh\nsource /tmp/install_magento.sh ${huaweicloud_vpc_eip.eip_elb.address} ${huaweicloud_rds_instance.rds_instance.fixed_ip} ${var.rds_password} ${huaweicloud_dcs_instance.redis_instance.private_ip} ${var.redis_password} ${var.elasticsearch_password} ${var.elasticsearch_host} ${huaweicloud_sfs_turbo.sfs_turbo.export_location} ${var.magento_admin_firstname} ${var.magento_admin_lastname} ${var.magento_admin_password} ${var.magento_admin_email} ${var.magento_public_key} ${var.magento_private_key} ${var.ecs_name}-ims ${huaweicloud_cbr_vault.cbr_vault.id} > /tmp/install_magento.log 2>&1\nrm -rf /tmp/install_magento.sh"
    user_data = "#!/bin/bash\necho 'root:${var.ecs_password}' | chpasswd"
}

resource "huaweicloud_compute_instance" "magento2" {
  depends_on                  = [huaweicloud_compute_instance.magento1]
  count                       = var.ecs_number - 1
  name                        = "${var.ecs_name}-${count.index + 2}"
  image_id                    = data.huaweicloud_images_image.image.id
  flavor_id                   = "s6.xlarge.2"
  security_group_ids          = [huaweicloud_networking_secgroup.secgroup.id]
  system_disk_type            = "SSD"
  system_disk_size            = 40
  admin_pass                  = var.ecs_password
  delete_disks_on_termination = true
  network {
    uuid = local.subnet_id
  }
  scheduler_hints {
    group = huaweicloud_compute_servergroup.servergroup.id
  }
  agency_name = huaweicloud_identity_agency.identity_agency.name
  # agent_list = "hss,ces"
  eip_id    = huaweicloud_vpc_eip.eip_ecs[count.index + 1].id
  user_data = "#!/bin/bash\necho 'root:${var.ecs_password}' | chpasswd\nwget -P /tmp/ https://solution-as-code-w8das.obs.eu-central-6001.apistack.one.hu/magento2-base-ecs/modify_specification.sh\nchmod +x /tmp/modify_specification.sh\nsh /tmp/modify_specification.sh ${var.ecs_name}-ims ${var.ecs_password} > /tmp/modify_specification.log 2>&1\nrm -rf /tmp/modify_specification.sh"
}

resource "huaweicloud_lb_loadbalancer" "elb" {
  name          = var.elb_name
  vip_subnet_id = var.subnet_ipv4_id
}

resource "huaweicloud_lb_listener" "elb_listener" {
  loadbalancer_id = huaweicloud_lb_loadbalancer.elb.id
  protocol        = "TCP"
  protocol_port   = "80"
}

resource "huaweicloud_lb_pool" "elb_pool" {
  lb_method   = "ROUND_ROBIN"
  listener_id = huaweicloud_lb_listener.elb_listener.id
  name        = var.elb_name
  protocol    = "TCP"
}

resource "huaweicloud_lb_member" "elb_member1" {
  address       = huaweicloud_compute_instance.magento1.access_ip_v4
  pool_id       = huaweicloud_lb_pool.elb_pool.id
  protocol_port = 80
  subnet_id     = var.subnet_ipv4_id
  weight        = 1
}

resource "huaweicloud_lb_member" "elb_member2" {
  count         = var.ecs_number - 1
  address       = huaweicloud_compute_instance.magento2[count.index].access_ip_v4
  pool_id       = huaweicloud_lb_pool.elb_pool.id
  protocol_port = 80
  subnet_id     = var.subnet_ipv4_id
  weight        = 1
}

resource "huaweicloud_lb_monitor" "elb_monitor" {
  delay       = 5
  max_retries = 3
  pool_id     = huaweicloud_lb_pool.elb_pool.id
  timeout     = 3
  type        = "TCP"
}

resource "huaweicloud_vpc_eip_associate" "eip_associate_appgateway" {
  port_id   = huaweicloud_lb_loadbalancer.elb.vip_port_id
  public_ip = huaweicloud_vpc_eip.eip_elb.address
}

output "magento_address" {
  value = "After the deployment is successful, the script starts to be executed. Wait for about 30 minutes (affected by network fluctuation). You can log in to the ECS to view the script execution progress in /tmp/install_magento.log on Magento server 1. For other Magento servers, check whether their images are ${var.ecs_name}-ims on the console. If yes, all Magento servers are successfully deployed. Enter http://${huaweicloud_vpc_eip.eip_elb.address} in the address box of the browser to access the website."
}