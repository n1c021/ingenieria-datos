# ── Módulo de red ──────────────────────────────────────

resource "aws_vpc" "data_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.environment}-data-vpc" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.data_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.environment}-private-${count.index}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.data_vpc.id
  tags   = { Name = "${var.environment}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# S3 Gateway Endpoint — 
# Se define un endpoint privado hacia S3 y asociado a la tabla de rutas privada,
# para que los recursos de las subredes privadas puedan acceder a S3. 
# Flink puede acceder y escribir en S3 a través de la red de AWS sin salir a internet
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.data_vpc.id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.private.id]
  tags            = { Name = "${var.environment}-s3-endpoint" }
}

# Bucket del data lake — usado por Flink checkpoints
resource "aws_s3_bucket" "datalake" {
  bucket = "${var.environment}-datalake-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${var.environment}-datalake" }
}

# Se bloquea el acceso publico a S3:
resource "aws_s3_bucket_public_access_block" "datalake" {
  bucket                  = aws_s3_bucket.datalake.id
  block_public_acls       = true # Bloquea ACL publicas
  ignore_public_acls      = true # Ignora ACLs públicas
  block_public_policy     = true # Bloquea políticas al bucket
  restrict_public_buckets = true # Restringe el acceso cuando existe una política pública
}

data "aws_caller_identity" "current" {}
