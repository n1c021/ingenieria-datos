
# ------------------------------------------------------------------------------
# Definicion del recurso aws_kinesis_stream 
# KINESIS DATA STREAM (KDS) 
# - Modo PROVISIONED
# - 2 shards
# ------------------------------------------------------------------------------
resource "aws_kinesis_stream" "main" {
  name             = var.stream_name
  shard_count      = var.shard_count # conteo de shards
  retention_period = 24              # horas, default 24

  # Stream con cifrado KMS
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = {
    Name        = var.stream_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# IAM ROLE PARA FIREHOSE
# - Leer del stream de Kinesis
# - Escribir en S3
# - Logs en CloudWatch
# ------------------------------------------------------------------------------
resource "aws_iam_role" "firehose" {
  name = "firehose-kinesis-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

# Se aplica la politica de rol para tener permisos de lectura del stream de Kinesis
resource "aws_iam_role_policy" "firehose" {
  name = "firehose-kinesis-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords"
        ]
        Resource = aws_kinesis_stream.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject", #Escritura en S3
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:AbortMultipartUpload",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# KINESIS DATA FIREHOSE (KDF) 
# - Origen (Source): KDS 
# - Destino: Bucket de S3
# ------------------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "main" {
  name        = "ingesta-${var.stream_name}"
  destination = "extended_s3"


  # Origen: Kinesis Data Stream (patrón híbrido)
  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.main.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = "arn:aws:s3:::${var.bucket_name}"

    # Prefijos dinámicos (Bronze layer organizada por año)
    prefix = "ingesta/year=!{timestamp:yyyy}/"
    # Se agrega el tipo de error en caso de fallo
    error_output_prefix = "ingesta-errores/year=!{timestamp:yyyy}/type=!{firehose:error-output-type}"

    # Política de buffering agresiva para desarrollo
    buffering_size     = var.buffer_size_mb      # 5 MB
    buffering_interval = var.buffer_interval_sec # 60 segudos

    # Compresión recomendada
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesis-firehose/${var.stream_name}"
      log_stream_name = "S3Delivery"
    }
  }

  tags = {
    Name        = "ingesta-${var.stream_name}"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# OBSERVABILIDAD - Firehose en CloudWatch
# Alarmas de CloudWatch para monitorear:
# -ReadProvisionedThroughputExceeded 
# -WriteProvisionedThroughputExceeded
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  alarm_name          = "kinesis-read-throttled-${var.stream_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ReadProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Lecturas excediendo la capacidad provisionada del stream"
  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  alarm_name          = "kinesis-write-throttled-${var.stream_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "WriteProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Escrituras excediendo la capacidad provisionada del stream"
  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }
}
