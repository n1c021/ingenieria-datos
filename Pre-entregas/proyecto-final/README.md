# Guia para el configuracion y despliegue de Infraestructura

## 0) Configuracion previa

**0.1) Editar archivo de `terraform/environments/dev/backend-dev-s3.hcl`**

```hcl
bucket = "<nombre-bucket-S3>"
region = "us-east-1"
```

**0.2) Editar archivo de `terraform/environments/dev/terraform.tfvars`**

```hcl
redshift_admin_password = "<CAMBIAME!>"
```

## **1) Despliegue de infraestructura con Terraform**


**Inicializar y aplicar la infraestructura base**


Desde bash, parado en `terraform/environments/dev`:

```bash
cd terraform/environments/dev/
```
```bash
terraform init -backend-config=backend-dev-s3.hcl
```
```bash
terraform plan
```
```bash
terraform apply
```

## 2) Apache Flink 

**2.1) Compilar el codigo de Apache Flink**

```bash
cd ../../../flink-app/
```
```bash
mvn clean package -DskipTests
```
```bash
ls -larth target/lakehouse-streaming-job-1.0.0.jar
```

**2.2) Subir el jar y segundo apply**

```bash
export LAKEHOUSE_BUCKET=$(cd terraform/environments/dev && terraform output -raw datalake_bucket_name)
```
```bash
aws s3 cp target/lakehouse-streaming-job-1.0.0.jar s3://$LAKEHOUSE_BUCKET/flink-artifacts/lakehouse-streaming-job.jar
```
```bash
aws s3 ls s3://dev-datalake-880287985194/flink-artifacts/lakehouse-streaming-job.jar
```
```bash
cd ../terraform/environments/dev
```
```bash
terraform apply
```
**2.3) Iniciar la aplicacion de Flink**
```bash
cd ../../../flink-app/
```
```bash
FLINK_APP_NAME=$(terraform output -raw flink_app_name)
```

```bash
aws kinesisanalyticsv2 start-application \
  --application-name $FLINK_APP_NAME \
  --region us-east-1 \
  --run-configuration '{"ApplicationRestoreConfiguration":{"ApplicationRestoreType":"SKIP_RESTORE_FROM_SNAPSHOT"}}'
```
**2.4) Comprobar el estado hasta que diga running**
```bash
aws kinesisanalyticsv2 describe-application --application-name $FLINK_APP_NAME \
  --region us-east-1 \
  --query 'ApplicationDetail.{Status:ApplicationStatus,Version:ApplicationVersionId}'
```

## 3) Probar Kinesis + Flink + Iceberg

```bash
cd ../terraform/environments/dev
```
```bash
export KINESIS_STREAM_NAME=$(terraform output -raw kinesis_stream_name)
```
```bash
cd ../../../test/
```
```bash
pip install boto3
```
```bash
export KINESIS_STREAM_NAME=$KINESIS_STREAM_NAME
```
```bash
export AWS_REGION=us-east-1
```
```bash
python3 prueba_en_vivo.py
```