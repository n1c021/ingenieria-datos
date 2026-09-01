# Ambiente o entorno (Dev, prod,etc)
variable "environment" {
  type    = string
  default = "dev"
}
# Region de AWS a utilizar
variable "region" {
  type    = string
  default = "us-east-1"
}
# Rango de direcciones IP Privadas de un VPC
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
#Canidad de Shards
variable "shard_count" {
  type    = number
  default = 2
}
