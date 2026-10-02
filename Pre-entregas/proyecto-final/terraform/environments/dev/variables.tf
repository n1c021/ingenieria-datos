variable "environment" {
  type        = string
  description = "Nombre del entorno (dev, prod)"
  default     = "dev"
}

variable "region" {
  type        = string
  description = "Nombre de la region de AWS"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "Rango de direcciones IP Privadas de un VPC"
  default     = "10.0.0.0/16"
}

variable "bucket" {
  type        = string
  description = "Nombre del bucket de S3"
  default     = "coderhouse-tfstate-backend-nbalbi-2026-prentrega1-dev"
}

variable "shard_count" {
  type        = number
  description = "Cantidad de shards (2 MB/s de entrada => 2 shards)"
  default     = 2
}

variable "redshift_admin_password" {
  type        = string
  description = "Contraseña del administrador de Redshift"
  sensitive   = true
}

variable "redshift_RPU" {
  type        = number
  description = "Numero de RPU base minimos"
  default     = 8
}