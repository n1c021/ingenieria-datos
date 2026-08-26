terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ------------------------------------
# MÓDULO DE INGESTA DE DATOS (KINESIS)
# ------------------------------------

module "kinesis" {
  source      = "../../modules/Kinesis"
  environment = "dev"

  stream_name = "clicks-ecommerce-dev"
  shard_count = 2

  bucket_name = "coderhouse-tfstate-backend-nbalbi-2026-prentrega1-dev"

  # Buffering agresivo para ver resultados rápido en dev
  buffer_size_mb      = 5
  buffer_interval_sec = 60
}


# ------------------------------------------------------------------------------
# OUTPUTS
# ------------------------------------------------------------------------------
output "stream_arn" {
  value = module.kinesis.stream_arn
}

output "stream_name" {
  value = module.kinesis.stream_name
}

output "firehose_arn" {
  value = module.kinesis.firehose_arn
}

output "firehose_name" {
  value = module.kinesis.firehose_name
}
