# ProsperApp

Aplicación web para gestionar proyectos personales. El frontend se sirve con Nginx, la API está desarrollada con FastAPI y los datos se almacenan en PostgreSQL.

## Requisitos

- Docker
- Docker Compose v2
- Puertos disponibles `8080` para la aplicación y `5433` para PostgreSQL

## Levantar el proyecto

### 1. Levantar PostgreSQL

Desde la raíz del proyecto, ejecuta:

```bash
docker compose up -d postgres
```

Comprueba que la base de datos esté saludable:

```bash
docker compose ps postgres
```

El estado debe aparecer como `healthy`.

### 2. Inicializar la base de datos

En el primer arranque, PostgreSQL ejecuta automáticamente `schema_seed.sql`. Este archivo está montado dentro de `/docker-entrypoint-initdb.d/` y crea las tablas, índices, relaciones y datos iniciales.

Puedes verificar que el seed se haya aplicado consultando los proyectos:

```bash
docker compose exec postgres \
  psql -U prosperapp -d prosperapp \
  -c "SELECT id_proyecto, nombre FROM proyecto ORDER BY id_proyecto;"
```

La consulta debe devolver tres proyectos iniciales.

> El script automático solo se ejecuta cuando el volumen de PostgreSQL está vacío. Los siguientes arranques reutilizan los datos persistidos en `postgres_data`.

### 3. Levantar la API y Nginx

Cuando PostgreSQL esté saludable, ejecuta:

```bash
docker compose up -d --build api nginx
```

También puedes levantar todo el proyecto desde cero con un único comando:

```bash
docker compose up -d --build --wait
```

## Acceso

| Servicio | Dirección |
|---|---|
| Aplicación | <http://localhost:8080> |
| Documentación de la API | <http://localhost:8080/api/docs> |
| PostgreSQL desde el host | `localhost:5433` |

Credenciales de desarrollo de PostgreSQL:

| Campo | Valor |
|---|---|
| Base de datos | `prosperapp` |
| Usuario | `prosperapp` |
| Contraseña | `prosperapp123` |

## Reinicializar la base de datos

Para eliminar todos los datos persistidos y volver a ejecutar `schema_seed.sql`:

```bash
docker compose down -v
docker compose up -d postgres
docker compose up -d --build api nginx
```

> ADVERTENCIA: `docker compose down -v` elimina definitivamente el volumen y todos los datos de la base.

Si necesitas aplicar el seed manualmente sobre la base actual, ejecuta:

```bash
docker compose exec -T postgres \
  psql -U prosperapp -d prosperapp < schema_seed.sql
```

`schema_seed.sql` elimina y vuelve a crear las tablas, por lo que esta operación también reemplaza los datos existentes.

## Detener el proyecto

Detén los contenedores sin borrar la base de datos:

```bash
docker compose down
```

El volumen `postgres_data` permanecerá disponible para el próximo arranque.
