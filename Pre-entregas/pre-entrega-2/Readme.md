# Pre-Entrega 2: ingesta real-time sobre el entorno base

En esta pre-entrega se implementa mediante código (HCL/Terraform):

- **Módulo de Streaming**: módulo de Terraform ```modules/Kinesis```
 que encapsula el stream **Kinesis Data Stream (KDS)** definido como el recurso ```aws_kinesis_stream``` y el delivery stream **Kinesis Data Firehose (KDF)** definido como el recurso ```aws_kinesis_firehose_delivery_stream```.

- **Integración Firehose-S3**: Se configura el destino de Firehose hacia el bucket S3 creado en la pre-entrega 1 cuyo nombre es ```coderhouse-tfstate-backend-nbalbi-2026-prentrega1-dev``` 

-**Observabilidad de Ingesta**: Alarmas de CloudWatch para monitorear ```ReadProvisionedThroughputExceeded``` y ```WriteProvisionedThroughputExceeded```.

Teniendo ya creado el bucket en S3 coderhouse-tfstate-backend-nbalbi-2026-prentrega1-dev se procede con el siguiente despliegue:

## **1) Despliegue del entorno dev**

```bash
cd environments/dev
```
**1.1) Inicializar el directorio con los archivos de terraform**

```bash
terraform init
``` 
**1.2) Validar sintaxis de Terraform**

```bash
terraform validate
```
**1.3) Aplicar despliegue en AWS**

```bash
terraform apply -auto-approve
```

## **2) Prueba de Ingesta**

**2.1) Comando de AWS CLI para generar un evento de prueba al stream**

```bash
aws kinesis put-record \
  --stream-name "clicks-ecommerce-dev" \
  --partition-key "test_user_1" \
  --data '{"user_id": 101, "event":"click_product", "timestamp": "2026-08-25T23:40:00Z"}' \
  --region us-east-1 \
  --cli-binary-format raw-in-base64-out
```
**Salida:**

```bash
{
    "ShardId": "shardId-000000000000",
    "SequenceNumber": "49677733998332438015530362975952670862602076198822477826",
    "EncryptionType": "KMS"
}
```
**2.2) Comprobar el archivo generado por Firehose en el bucket S3**
```bash
aws s3 ls s3://coderhouse-tfstate-backend-nbalbi-2026-prentrega1-dev/ --recursive --human-readable
```

**Salida:**

```bash
2026-08-25 23:41:41   97 Bytes ingesta/year=2026/ingesta-clicks-ecommerce-dev-1-2026-08-26-02-40-40-1adca4f3-beaa-4077-9efe-f72146f46d66.gz
```