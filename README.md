# Web Institucional Backend

Backend headless de la Universidad Distrital basado en Drupal 11, JSON:API,
Composer y Docker. Este repositorio contiene exclusivamente el CMS, su
configuración y su imagen de ejecución.

## Requisitos

- Docker Desktop o Docker Engine con Compose
- Git
- Composer 2.x y PHP 8.3+ solo si se trabajará fuera de Docker

## Desarrollo local

Desde la raíz que contiene ambos repositorios y `docker-compose.yml`:

```bash
cp web_institucional_backend/.env.example web_institucional_backend/.env
```

Edita `web_institucional_backend/.env` y define contraseñas locales para `DB_PASSWORD`,
`DB_ROOT_PASSWORD` y un valor aleatorio para `HASH_SALT`.

Si trabajas directamente con PHP o tu IDE necesita las dependencias, ejecuta
desde `web_institucional_backend/`:

```bash
composer install
```

La imagen del backend se construye desde la raíz que contiene
`docker-compose.yml`:

```bash
docker compose build backend
```

Para ejecutar Drupal se necesita una instancia MySQL accesible. En el entorno
local compartido, el Compose de la raíz crea MySQL y publica Drupal en
`http://localhost:8080`.

## Integración con Docker Compose

La estructura esperada por el Compose local es:

```text
web_institucional/
├── docker-compose.yml
├── web_institucional_backend/
└── web_institucional_frontend/
```

Desde el directorio que contiene `docker-compose.yml`:

```bash
# Edita web_institucional_backend/.env antes de continuar.
docker compose config
docker compose up -d --build db backend
```

El servicio queda disponible en:

- Drupal: http://localhost:8080
- JSON:API: http://localhost:8080/jsonapi
- Login administrativo: http://localhost:8080/user/login

Las imágenes públicas cargadas en Drupal se conservan en el volumen
`drupal_files` y se sirven desde
`http://localhost:8080/sites/default/files/`. El frontend usa esta URL desde
el navegador; S3 no es necesario durante el desarrollo local.

## Primera instalación

Desde la raíz del entorno Compose, carga las variables y ejecuta la
instalación una sola vez:

```bash
set -a
source web_institucional_backend/.env
set +a

docker compose exec backend vendor/bin/drush site:install standard \
  --db-url="mysql://${DB_USERNAME}:${DB_PASSWORD}@db:3306/${DB_DATABASE}" \
  --site-name="Universidad Distrital" \
  --account-name=admin \
  --account-pass='cambia-esta-clave' \
  --locale=es -y

docker compose exec backend vendor/bin/drush en jsonapi -y
docker compose exec backend vendor/bin/drush en redirect -y
docker compose exec backend vendor/bin/drush cache:rebuild
```

Cambia la contraseña administrativa inmediatamente después de la instalación.

## Configuración de Drupal

- `web/sites/default/settings.php` obtiene la conexión de base de datos,
  `hash_salt`, hosts confiables y la ruta de sincronización desde variables de
  entorno.
- `web/sites/default/services.yml` habilita CORS para el frontend local.
- `config/sync/` contiene la configuración exportada de Drupal.
- `web/sites/default/files/` contiene archivos subidos y no debe versionarse.

Para importar configuración versionada:

```bash
docker compose exec backend vendor/bin/drush config:import -y
docker compose exec backend vendor/bin/drush cache:rebuild
```

Para aplicar un despliegue completo:

```bash
docker compose exec backend vendor/bin/drush deploy
```

Para exportar cambios hechos en Drupal desde la raíz del entorno Compose:

```bash
docker compose exec backend vendor/bin/drush config:export -y
docker compose exec backend tar -cf - -C /var/www/html config/sync | tar -xf - -C web_institucional_backend
```

Después revisa los archivos exportados en `config/sync/` antes de publicarlos.

## Contenido y archivos

La configuración exportada no incluye artículos, usuarios ni archivos
subidos. Para compartir contenido entre entornos se necesita un respaldo de
la base de datos y una copia de `web/sites/default/files/`.

No subas al repositorio:

- `.env`
- Dumps `.sql` o `.sql.gz`
- `web/sites/default/files/`
- Credenciales, certificados o claves privadas

En Compose, los directorios `web/sites/default/files` y
`web/sites/default/private` se conservan en volúmenes Docker separados. Los
binarios no se almacenan en la base de datos ni en Git.

## Archivos y almacenamiento S3

En desarrollo local, Drupal sirve los archivos públicos desde el volumen
`drupal_files`. En producción, los archivos públicos deben almacenarse en S3
y Drupal debe devolver sus URLs públicas mediante JSON:API. La alternativa
recomendada es:

1. Drupal recibe el archivo y lo guarda en un bucket S3 privado.
2. CloudFront sirve los objetos mediante Origin Access Control (OAC).
3. Drupal genera URLs con el dominio de CloudFront.
4. El frontend consume esas URLs sin copiar los archivos a su propio bucket.

El bucket de archivos debe tener permisos privados y una política que permita
acceso únicamente desde la distribución CloudFront. La integración de Drupal
con S3 todavía debe configurarse para producción, junto con sus credenciales y
la política del bucket. No se deben guardar credenciales en este repositorio.
La imagen actual conserva el almacenamiento local para desarrollo; antes del
despliegue se debe instalar y configurar el adaptador S3 elegido para Drupal.

## Variables principales

| Variable | Uso |
| --- | --- |
| `DB_DATABASE` | Nombre de la base de datos |
| `DB_USERNAME` | Usuario de Drupal |
| `DB_PASSWORD` | Contraseña del usuario de Drupal |
| `DB_ROOT_PASSWORD` | Contraseña root de MySQL local |
| `DB_HOST` | Host de MySQL; en Compose es `db` |
| `DB_PORT` | Puerto de MySQL; normalmente `3306` |
| `HASH_SALT` | Sal única para Drupal |
| `TRUSTED_HOST_PATTERN` | Hosts permitidos por Drupal |

En producción, las variables deben gestionarse mediante secretos de AWS, no
mediante archivos `.env` dentro de la imagen.

El origen permitido por CORS debe incluir el dominio real del frontend cuando
se conozca. La configuración versionada actual permite `http://localhost:3000`
para desarrollo local.

## Despliegue del backend en AWS

La imagen de este repositorio se publica en Amazon ECR y se ejecuta en ECS
Fargate detrás de un Application Load Balancer. La base de datos de producción
debe ser Amazon RDS for MySQL; el servicio `db` de este Compose es únicamente
para desarrollo local. Inyecta en la task definition `DB_DATABASE`,
`DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `HASH_SALT` y
`TRUSTED_HOST_PATTERN` desde AWS Secrets Manager o Systems Manager Parameter
Store.

El balanceador debe comprobar `GET /user/login` en el puerto 80. El frontend
necesita acceso HTTPS al dominio público de la API y a JSON:API. Las imágenes
de producción no deben depender del sistema de archivos local del contenedor:
Drupal debe devolver URLs del dominio CloudFront que sirve el bucket S3.

El `Dockerfile` usa la imagen `composer:2` únicamente como etapa de compilación
para copiar Composer y construir dependencias. No se crea un servicio Composer
en Compose: el runtime del backend es un único contenedor PHP-FPM + Nginx.

## Integración con el frontend

El frontend independiente consume la API publicada por este backend durante su
build estático. Drupal debe exponer JSON:API por HTTPS y devolver aliases,
metadata y URLs de imágenes válidas. La configuración y el código de Next.js
se mantienen en `web_institucional_frontend/`.
