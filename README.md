# Auto Auditoría

Sistema universitario de auditoría configurable para PostgreSQL. Permite seleccionar tablas, columnas y operaciones que se deben monitorear, instalar triggers para capturar cambios y consultar el historial desde una interfaz web.

## Objetivo

Registrar históricamente modificaciones realizadas en tablas configuradas, conservando la operación, fecha, usuario, contexto disponible y valores anteriores y nuevos de las columnas auditadas.

## Funcionalidades

- Sincroniza las tablas y columnas disponibles desde el diccionario de datos de PostgreSQL.
- Permite configurar la auditoría por esquema, tabla, columna y operación: `insert`, `update` y `delete`.
- Instala triggers `AFTER` en cada tabla de origen configurada.
- Guarda eventos y detalles en una bitácora central del esquema `trazabilidad`.
- Conserva snapshots `JSONB` de las filas anterior y nueva, la clave de la fila y el contexto disponible del evento.
- Registra el usuario de PostgreSQL y, cuando se usa la interfaz web, el usuario de aplicación.
- Permite consultar el historial por usuario, columna, esquema, tabla, operación y rango de fechas.
- Permite exportar resultados del historial a CSV.
- Incluye la tabla de demostración `public.clientes_demo`.
- Incluye una interfaz Flask con perfiles de operador, auditor y administrador.
- Incluye pruebas funcionales y pruebas de rendimiento con `EXPLAIN (ANALYZE, BUFFERS)`.

## Tecnologías

- PostgreSQL 18
- PL/pgSQL
- Ubuntu 26.04 LTS como entorno objetivo
- Python 3, Flask y psycopg
- HTML y CSS
- DBeaver para ejecutar y revisar scripts SQL
- Draw.io para editar diagramas

## Estructura del proyecto

```text
.
├── Documentacion_Despliegue/
│   └── Documentacion_Tecnica_Auto_Auditoria.pdf
├── UML/
│   └── Diagramas editables y exportaciones
├── 00_crear_base.sql
├── 01_crear_schema.sql
├── 02_esquema_tablas.sql
├── 03_funciones.sql
├── 04_permisos.sql
├── 05_configuracion_demo.sql
├── 06_consultas_historial.sql
├── 07_pruebas_funcionales.sql
├── 08_pruebas_rendimiento.sql
├── 09_contexto_usuario_web.sql
├── 10_actualizar_funcion_usuario_web.sql
├── README.md
└── web/
    ├── app.py
    ├── .env.example
    ├── requirements.txt
    ├── README.md
    ├── templates/
    └── static/
```

La carpeta `Documentacion_Despliegue/` contiene la documentación técnica del proyecto. La carpeta `UML/` contiene los diagramas editables de Draw.io y sus exportaciones de lectura, por ejemplo PNG o PDF.

## Documentación técnica

El documento técnico incluye el diagrama entidad-relación, el diccionario de datos, el manual de configuración de auditoría por tabla y el procedimiento de instalación y despliegue de triggers.

[Consultar la documentación técnica en PDF](Documentacion_Despliegue/Documentacion_Tecnica_Auto_Auditoria.pdf)

## Modelo de datos

El esquema `trazabilidad` contiene estas entidades principales:

- `trz_tabla_origen`: tablas registradas para auditoría.
- `trz_columna_origen`: columnas pertenecientes a cada tabla de origen.
- `trz_tipo_operacion`: catálogo de operaciones admitidas.
- `trz_regla_auditoria`: operaciones habilitadas para una columna.
- `trz_usuario`: referencia opcional al usuario PostgreSQL auditado.
- `trz_estacion`: catálogo de estaciones de trabajo.
- `trz_evento`: cabecera del evento, con contexto y snapshots.
- `trz_cambio_columna`: valores anterior y nuevo de cada columna registrada.

`public.clientes_demo` es una tabla de ejemplo que se administra desde la interfaz. La configuración identifica las tablas de origen por esquema y nombre; por eso no hay una clave foránea física desde la configuración hacia cada tabla auditada.

## Requisitos previos

- PostgreSQL 18 instalado y en ejecución.
- Una cuenta PostgreSQL autorizada para crear la base, el esquema, las tablas, las funciones y los roles.
- Python 3 instalado en Ubuntu.
- DBeaver para ejecutar los scripts SQL, si se desea utilizar una interfaz gráfica.
- Git para clonar el repositorio.

## Instalación de la base de datos

Ejecuta los scripts con una conexión activa a la base indicada en cada paso. En DBeaver, verifica la conexión seleccionada antes de ejecutar cada archivo.

### 1. Crear la base de datos

Conéctate a la base de mantenimiento `postgres` y ejecuta:

```text
00_crear_base.sql
```

La creación de una base de datos debe ejecutarse fuera de una transacción.

### 2. Instalar el esquema y los objetos

Conéctate a `control_cambios_db` y ejecuta los archivos en este orden:

```text
01_crear_schema.sql
02_esquema_tablas.sql
03_funciones.sql
09_contexto_usuario_web.sql
10_actualizar_funcion_usuario_web.sql
04_permisos.sql
05_configuracion_demo.sql
06_consultas_historial.sql
```

Las migraciones `09` y `10` agregan el snapshot del usuario de la aplicación web y actualizan la función que registra los cambios.

### 3. Conceder el rol administrativo

Si la interfaz web debe configurar auditoría, concede el rol administrativo a la cuenta PostgreSQL que usa la aplicación. Ejecuta este comando con una cuenta autorizada y reemplaza `autoaudit_app` si utilizas otro usuario:

```sql
GRANT autoaudit_admin TO autoaudit_app;
```

Los perfiles de la interfaz web no son roles PostgreSQL separados. La aplicación utiliza la cuenta configurada en `AUTOAUDIT_DB_USER`; el rol `autoaudit_admin` habilita las operaciones administrativas de auditoría.

### 4. Ejecutar las pruebas

Ejecuta `07_pruebas_funcionales.sql` para revisar los casos de `INSERT`, `UPDATE` y `DELETE`. Sus bloques de prueba utilizan `ROLLBACK`, por lo que los registros de prueba no quedan guardados.

Ejecuta los bloques de `08_pruebas_rendimiento.sql` según los comentarios del archivo. Conserva las salidas de `EXPLAIN (ANALYZE, BUFFERS)` para documentar las mediciones. Repite las mediciones para comparar distintos tamaños de lote y el comportamiento con auditoría activada y desactivada.

## Advertencias sobre scripts destructivos

> Ejecuta estos archivos únicamente en una instalación nueva o en una base de demostración. Haz un respaldo antes de continuar si la base contiene información que debas conservar.

- `01_crear_schema.sql` elimina y vuelve a crear el esquema `trazabilidad` con `CASCADE`. Se perderán las tablas, funciones y datos que existan dentro de ese esquema.
- `05_configuracion_demo.sql` elimina y vuelve a crear `public.clientes_demo` con `CASCADE`. Se perderán los datos existentes en esa tabla.
- Las pruebas pueden revertir sus cambios con `ROLLBACK`. Aun así, los valores de secuencias de identidad pueden avanzar.

## Instalación de la interfaz web en Ubuntu

Desde la carpeta donde quieras guardar el proyecto, clona el repositorio y entra a la carpeta de la interfaz:

```bash
git clone https://github.com/cristop777/DB1_Proyecto_Final.git
cd DB1_Proyecto_Final/web
```

Crea y activa un entorno virtual, instala las dependencias y copia el archivo de ejemplo:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

Edita `web/.env` y completa los valores con las credenciales de tu instalación. Usa los nombres de variables incluidos en `web/.env.example`. El archivo podría contener variables como estas:

```ini
AUTOAUDIT_DB_HOST=127.0.0.1
AUTOAUDIT_DB_PORT=5432
AUTOAUDIT_DB_NAME=control_cambios_db
AUTOAUDIT_DB_USER=autoaudit_app
AUTOAUDIT_DB_PASSWORD=CAMBIA_POR_LA_CLAVE_DE_POSTGRESQL

AUTOAUDIT_WEB_USER=admin
AUTOAUDIT_WEB_PASSWORD_HASH=PEGA_AQUI_EL_HASH_DEL_ADMIN

AUTOAUDIT_WEB_CLIENT_USER=operador
AUTOAUDIT_WEB_CLIENT_PASSWORD_HASH=PEGA_AQUI_EL_HASH_DEL_OPERADOR

AUTOAUDIT_WEB_AUDITOR_USER=auditor
AUTOAUDIT_WEB_AUDITOR_PASSWORD_HASH=PEGA_AQUI_EL_HASH_DEL_AUDITOR

FLASK_SECRET_KEY=PEGA_AQUI_UNA_CLAVE_ALEATORIA_LARGA
AUTOAUDIT_OPEN_BROWSER=true
```

Si las variables del archivo `.env.example` tienen nombres distintos, conserva los nombres de ese archivo y completa sus valores correspondientes.

### Generar hashes para las contraseñas web

Activa el entorno virtual y ejecuta este comando una vez por cada cuenta web. Escribe la contraseña cuando se solicite y copia el hash resultante en la variable correspondiente de `.env`:

```bash
python -c 'from getpass import getpass; from werkzeug.security import generate_password_hash; print(generate_password_hash(getpass("Contraseña: ")))'
```

Genera una clave secreta de Flask con:

```bash
python -c 'import secrets; print(secrets.token_hex(32))'
```

Pega el resultado en `FLASK_SECRET_KEY`.

### Iniciar la aplicación

Desde la carpeta `web`, con el entorno virtual activo, ejecuta:

```bash
python app.py
```

Si usas una máquina virtual Ubuntu sin escritorio, reenvía el puerto `5000` desde la sección **Ports / Puertos** de VS Code y abre en el navegador la dirección que VS Code muestre. Para detener la aplicación, presiona `Ctrl+C` en la terminal donde se está ejecutando.

## Perfiles de la interfaz

- **Operador:** puede usar la página de clientes demo.
- **Auditor:** puede usar clientes demo y consultar el historial.
- **Administrador:** puede usar clientes demo, consultar el historial y configurar auditoría.

Estos perfiles pertenecen a Flask, no son cuentas PostgreSQL independientes. Las cuentas web comparten la conexión configurada en `AUTOAUDIT_DB_USER`. La bitácora conserva el usuario PostgreSQL en `usuario_snapshot` y el usuario de la interfaz en `usuario_aplicacion_snapshot`, cuando se dispone de ese contexto.

## Seguridad

- No publiques `web/.env` ni lo agregues a Git; contiene credenciales y claves privadas.
- Publica `web/.env.example`, que debe incluir nombres de variables y valores de ejemplo, nunca contraseñas reales.
- Quien descargue el proyecto debe copiar `.env.example` como `.env` y completar sus credenciales locales.
- No uses el superusuario PostgreSQL como cuenta permanente de la aplicación.
- Limita los permisos de la cuenta de la aplicación a los objetos y funciones que necesita.
- Restringe el acceso de escritura directa a las tablas de configuración y bitácora.
- Los snapshots pueden contener información personal o confidencial. Limita el acceso y define una política de retención adecuada.
- Registra y conserva direcciones IP de acuerdo con las políticas de privacidad aplicables.
- La aplicación está pensada para desarrollo y demostración local; no publiques directamente el servidor Flask de desarrollo en Internet.

## Solución de problemas

### Error de autenticación PostgreSQL

Si aparece `password authentication failed`, comprueba que `AUTOAUDIT_DB_USER` y `AUTOAUDIT_DB_PASSWORD` coincidan con el rol y la contraseña configurados en PostgreSQL. También confirma que PostgreSQL esté iniciado y que el host, puerto y base de datos sean correctos.

### No aparecen tablas en Configuración de auditoría

Verifica que:

- La aplicación esté conectada a `control_cambios_db`.
- La tabla exista y sea visible para la cuenta PostgreSQL de la aplicación.
- El diccionario se haya sincronizado desde la pantalla de configuración.
- La cuenta tenga los permisos necesarios para consultar el catálogo de PostgreSQL.

### El historial no muestra registros

Comprueba que la tabla tenga operaciones habilitadas, que el trigger de esa tabla exista y que la transacción que modificó los datos se haya confirmado. Los casos de prueba que terminan con `ROLLBACK` no dejan cambios persistentes.

### Error `current transaction is aborted`

Una sentencia anterior falló dentro de la transacción. Ejecuta `ROLLBACK` o finaliza la transacción fallida en DBeaver, corrige el primer error y vuelve a ejecutar el bloque.

## Recursos

- [Repositorio del proyecto en GitHub](https://github.com/cristop777/DB1_Proyecto_Final)
- [Documentación técnica en PDF](Documentacion_Despliegue/Documentacion_Tecnica_Auto_Auditoria.pdf)
- [README de la interfaz web](https://github.com/cristop777/DB1_Proyecto_Final/blob/main/web/README.md)
- [Diagramas UML](https://github.com/cristop777/DB1_Proyecto_Final/tree/main/UML)
