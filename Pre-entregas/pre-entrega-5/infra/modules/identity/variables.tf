
# Ambiente o entorno (Dev, prod,etc)
variable "environment" {
  type = string
}

# ARN del bucket S3 para el datalake arn:aws:s3:::mi-datalake
variable "datalake_bucket_arn" {
  type = string
}
#ARN del kinesis_stream
variable "kinesis_stream_arn" {
  type = string
}
