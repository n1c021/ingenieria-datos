# ── Rol de IAM para Redshift ──────────
data "aws_iam_policy_document" "redshift_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "redshift-serverless.amazonaws.com",
        "redshift.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "redshift_streaming_role" {
  name               = "${var.environment}-redshift-streaming-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume_role.json
}

data "aws_kms_alias" "kinesis" {
  name = "alias/aws/kinesis"
}

data "aws_iam_policy_document" "redshift_streaming_permissions" {
  statement {
    sid    = "KinesisStreamingRead"
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetShardIterator",
      "kinesis:GetRecords",
      "kinesis:ListShards",
    ]
    resources = [module.ingestion.kinesis_stream_arn]
  }

  # El stream de Kinesis esta cifrado con KMS (encryption_type = "KMS"
  # en modules/ingestion). Sin este permiso, Redshift puede describir
  # y listar el stream, pero no logra descifrar el contenido real de
  # los registros -- el sintoma es "Stream returned no new data" en
  # el refresh de la Materialized View, sin ningun error explicito.
  statement {
    sid       = "KinesisKmsDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.kinesis.target_key_arn]
  }

  statement {
    sid    = "GlueCatalogRead"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartitions",
      "glue:CreateDatabase"
    ]
    # Se configuran los minimos permisos de lectura sobre la tabla sensor_events y la bd lakehouse_db

    resources = ["arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:database/lakehouse_db",
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:table/lakehouse_db/sensor_events"
    ]
  }

  # ── S3: lectura de objetos Iceberg sobre sensor_events──────────────────────────────

  statement {
    sid    = "ReadIcebergMetadataAndData"
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "arn:aws:s3:::${module.network.datalake_bucket_name}/lakehouse/lakehouse_db.db/sensor_events/*"
    ]
  }


  # ── S3: acceso al bucket ────────────────────────────────────────

  statement {
    sid    = "ListIcebergBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      "arn:aws:s3:::${module.network.datalake_bucket_name}"
    ]
  }
}

resource "aws_iam_role_policy" "redshift_streaming_policy" {
  name   = "redshift-streaming-minimal-access"
  role   = aws_iam_role.redshift_streaming_role.id
  policy = data.aws_iam_policy_document.redshift_streaming_permissions.json
}

# ── Redshift Serverless: namespace (agrupa recursos) ───────────────
resource "aws_redshiftserverless_namespace" "lakehouse" {
  namespace_name       = "${var.environment}-lakehouse-ns"
  admin_username       = "admin_lakehouse"
  admin_user_password  = var.redshift_admin_password
  iam_roles            = [aws_iam_role.redshift_streaming_role.arn]
  default_iam_role_arn = aws_iam_role.redshift_streaming_role.arn
}

# ── Redshift Serverless: workgroup ───────────────────────
resource "aws_redshiftserverless_workgroup" "lakehouse" {
  namespace_name = aws_redshiftserverless_namespace.lakehouse.namespace_name
  workgroup_name = "${var.environment}-lakehouse-wg"
  base_capacity  = var.redshift_RPU

  # Todo el trafico pasa por la VPC, no por la red publica de AWS.
  # IMPORTANTE: con enhanced_vpc_routing = true, Redshift necesita UN
  # VPC Endpoint POR CADA SERVICIO al que se conecta (Kinesis, Glue,
  # etc). Sin el endpoint correspondiente, ese trafico no tiene por donde salir.
  enhanced_vpc_routing = true
  subnet_ids           = module.network.private_subnet_ids
}

resource "aws_security_group" "glue_endpoint" {
  name        = "${var.environment}-glue-endpoint-sg"
  description = "Permite trafico HTTPS desde la VPC hacia el endpoint de Glue"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "glue" {
  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.region}.glue"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [aws_security_group.glue_endpoint.id]
  private_dns_enabled = true
}

resource "aws_security_group" "kinesis_endpoint" {
  name        = "${var.environment}-kinesis-endpoint-sg"
  description = "Permite trafico HTTPS desde la VPC hacia el endpoint de Kinesis"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "kinesis" {
  vpc_id              = module.network.vpc_id
  service_name        = "com.amazonaws.${var.region}.kinesis-streams"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [aws_security_group.kinesis_endpoint.id]
  private_dns_enabled = true
}

# ── Outputs para usar en los scripts SQL y en la verificacion ─────
output "redshift_workgroup_endpoint" {
  value = aws_redshiftserverless_workgroup.lakehouse.endpoint
}

output "redshift_namespace_name" {
  value = aws_redshiftserverless_namespace.lakehouse.namespace_name
}

output "redshift_streaming_role_arn" {
  value = aws_iam_role.redshift_streaming_role.arn
}
