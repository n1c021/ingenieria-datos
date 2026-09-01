# Ambiente o entorno (Dev, prod,etc)
variable "environment" {
  type = string
}
# Cantidad de shards
variable "shard_count" {
  type    = number
  default = 2
}
# ARN del bucket S3 para el datalake arn:aws:s3:::mi-datalake
variable "datalake_bucket_arn" {
  type = string
}
