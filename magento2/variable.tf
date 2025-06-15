variable "vpc_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "subnet_ipv4_id" {
  type = string
}

variable "ecs_name" {
  type = string
}

variable "ecs_number" {
  type = number
}

variable "eip_bandwidth_size" {
  type = number
}

variable "cbr_vault_name" {
  type = string
}

variable "elb_name" {
  type = string
}

variable "security_group_name" {
  type = string
}

variable "redis_capacity" {
  type = number
}

variable "sfs_turbo_name" {
  type = string
}

variable "sfs_turbo_size" {
  type = number
}

variable "redis_name" {
  type = string
}

variable "redis_password" {
  type      = string
  sensitive = true
}

variable "rds_cpu" {
  type = number
}

variable "rds_memory" {
  type = number
}

variable "rds_password" {
  type      = string
  sensitive = true
}

variable "rds_name" {
  type = string
}

variable "rds_volume_size" {
  type = number
}

variable "elasticsearch_password" {
  type      = string
  sensitive = true
}

variable "ecs_password" {
  type      = string
  sensitive = true
}

variable "elasticsearch_host" {
  type = string
}

variable "magento_admin_firstname" {
  type = string
}

variable "magento_admin_lastname" {
  type = string
}

variable "magento_admin_password" {
  type      = string
  sensitive = true
}

variable "magento_admin_email" {
  type = string
}

variable "magento_public_key" {
  type      = string
  sensitive = true
}

variable "magento_private_key" {
  type      = string
  sensitive = true
}

variable "use_sample_data" {
  type    = bool
  default = false
}