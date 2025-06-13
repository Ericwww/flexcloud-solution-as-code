data "huaweicloud_availability_zones" "az" {}

data "huaweicloud_images_image" "image" {
  most_recent = true
  name        = "Ubuntu 20.04 server 64bit"
  visibility  = "public"
}

data "huaweicloud_images_image" "rhel" {
  most_recent = true
  name        = "Redhat Linux Enterprise 8.10 64bit"
  visibility  = "public"
}

data "huaweicloud_rds_flavors" "rds_flavor" {
  db_type       = "MySQL"
  db_version    = "5.7"
  instance_mode = "ha"
  vcpus         = var.rds_cpu
  memory        = var.rds_memory
}

data "huaweicloud_dcs_flavors" "dcs_flavors" {
  engine_version = "6.0"
  cache_mode     = "ha"
  capacity       = var.redis_capacity
}