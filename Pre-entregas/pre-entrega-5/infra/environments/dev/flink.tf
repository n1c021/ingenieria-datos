# ── AWS Managed Service for Apache Flink ────────────────────────

resource "aws_kinesisanalyticsv2_application" "flink_job" {
  name                   = "${var.environment}-lakehouse-flink-job"
  runtime_environment    = "FLINK-1_18"
  service_execution_role = module.identity.flink_execution_role_arn

  application_configuration {
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = module.network.datalake_bucket_arn
          file_key   = "flink-artifacts/lakehouse-streaming-job.jar"
        }
      }
      code_content_type = "ZIPFILE"
    }

    environment_properties {
      property_group {
        property_group_id = "FlinkAppProperties"
        property_map = {
          "KINESIS_STREAM_ARN" = module.ingestion.kinesis_stream_arn
          "LAKEHOUSE_BUCKET"   = module.network.datalake_bucket_name
        }
      }
    }

    flink_application_configuration {
      checkpoint_configuration {
        configuration_type            = "CUSTOM"
        checkpointing_enabled         = true  # Activa los checkpoints
        checkpoint_interval           = 60000 # valor en milisegundos: 60000 ms = 60 segundos = 1 minuto 
        min_pause_between_checkpoints = 5000  # valor en milisegundos: 5000 ms = 5 segundos de pausa entre checkpoints
      }

      parallelism_configuration {
        configuration_type   = "CUSTOM"
        parallelism          = 1     # Cantidad de tareas simultaneas que puede ejecutar Flink 
        parallelism_per_kpu  = 1     # Cantidad de tareas simultaneas que puede ejecutar Flink por Kinesis Processing Unit (KPU) 1KPU = 1vCPU + 4GB de RAM
        auto_scaling_enabled = false # Escalamiento automatico desactivado. AWS no aumentará o disminuirá automáticamente la capacidad de la aplicación basándose en la carga.
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }
    }
  }

  # El logging de CloudWatch 
  cloudwatch_logging_options {
    log_stream_arn = aws_cloudwatch_log_stream.flink_log_stream.arn
  }

  tags = { Name = "${var.environment}-lakehouse-flink-job" }
}

resource "aws_cloudwatch_log_group" "flink_log_group" {
  name              = "/aws/kinesis-analytics/${var.environment}-lakehouse-flink-job"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "flink_log_stream" {
  name           = "flink-log-stream"
  log_group_name = aws_cloudwatch_log_group.flink_log_group.name
}
