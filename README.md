Pre-Entrega 1:

En este caso de sube todo el material requerido en la pre-entrega 1 (carpeta nicolasbalbi-proyecto-dataops).

Para inicializar el entorno:

1) Validar credenciales activas
  aws sts get-caller-identity

2) Ejecutar el Bootstrap: Crea el bucket y la tabla requeridos para guardar el
estado remoto. El bucket de S3 que se creara tendra como nombre "coderhouse-tfstate-backend-nbalbi-2026-prentrega1-dev"

    cd bootstrap
   
    # Inicializar y aplicar

    terraform init
    terraform apply -auto-approve
   
    # Volver a la raíz del proyecto
    cd ..

4) Desplegar entorno dev/
   
    cd environments/dev
   
     1. Inicializar con conexión al Backend Remoto en S3

    terraform init

     2. Validar sintaxis de Terraform
    terraform validate

     3. Aplicar infraestructura en AWS
    terraform apply -auto-approve
  
