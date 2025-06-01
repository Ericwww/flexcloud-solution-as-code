variable "ecs_name" {
  type = string
  default = "es-demo"
}

variable "security_group_name" {
  type = string
  default = "es-demo"
}

variable "vpc_name" {
  type = string
  default = "es-demo"
}

variable "es_ecs_count" {
  type = number
  default = 3
}

variable "ecs_password" {
  type      = string
  sensitive = true
}