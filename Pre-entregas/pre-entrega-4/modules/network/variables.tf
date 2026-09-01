# Ambiente o entorno (Dev, prod,etc)
variable "environment" {
  type = string
}
# Rango de direcciones IP Privadas de un VPC
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "region" {
  type = string
}
