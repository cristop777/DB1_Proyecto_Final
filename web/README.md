# Auto Auditoría

Sistema universitario de auditoría configurable para PostgreSQL. Permite seleccionar tablas, columnas y operaciones que se deben monitorear; genera triggers para capturar cambios y ofrece una interfaz web para gestionar datos de demostración y consultar el historial.

## Objetivo

Registrar de forma histórica las modificaciones realizadas en tablas configuradas, conservando la operación, la fecha, el usuario, el origen y los valores anteriores y nuevos de las columnas auditadas.

## Características

- Sincroniza tablas y columnas disponibles desde el diccionario de PostgreSQL.
- Configura auditoría por esquema, tabla, columna y operación: `insert`, `update` y `delete`.
- Instala triggers `AFTER` sobre cada tabla origen configurada.
- Registra eventos y detalles en una bitácora central del esquema `trazabilidad`.
- Conserva snapshots JSON de la fila anterior y nueva, clave primaria, usuario PostgreSQL, usuario web, estación, IP y fecha del evento.
- Permite buscar el historial por usuario, columna, esquema, tabla, operación y rango de fechas; también puede exportarlo a CSV.
- Incluye la tabla de demostración `public.clientes_demo` y una interfaz Flask con perfiles de operador, auditor y administrador.
- Incluye scripts funcionales y pruebas de rendimiento con `EXPLAIN (ANALYZE, BUFFERS)`.

## Tecnologías

- PostgreSQL 18 y PL/pgSQL.
- Ubuntu 26.04 LTS como entorno objetivo del proyecto.
- DBeaver para ejecutar y revisar los scripts SQL.
- Python 3, Flask, psycopg y HTML/CSS para la interfaz web.
- Draw.io para editar diagramas; los diagramas y exportaciones se almacenan en `UML/`.

## Estructura del repositorio

```text
.
├── UML/                                  # Diagramas editables y exportaciones
├── 00_crear_base.sql                     # Crea control_cambios_db
├── 01_crear_schema.sql                   # Prepara el esquema trazabilidad
├── 02_esquema_tablas.sql                 # Crea tablas, claves e índices
├── 03_funciones.sql                      # Funciones de configuración y triggers
├── 04_permisos.sql                       # Rol y permisos administrativos
├── 05_configuracion_demo.sql             # Recrea y configura clientes_demo
├── 06_consultas_historial.sql            # Vista y consultas de historial
├── 07_pruebas_funcionales.sql            # Pruebas INSERT, UPDATE y DELETE
├── 08_pruebas_rendimiento.sql            # Pruebas de rendimiento
├── 09_contexto_usuario_web.sql           # Agrega el snapshot del usuario web
├── 10_actualizar_funcion_usuario_web.sql  # Actualiza el trigger de auditoría
└── web/
    ├── app.py
    ├── .env.example
    ├── requirements.txt
    ├── README.md
    ├── templates/
    └── static/
```

La carpeta `UML/` incluye el diagrama entidad-relación y cualquier diagrama complementario. Conviene guardar los archivos editables de Draw.io junto con exportaciones de lectura, por ejemplo PNG o PDF.

## Modelo de datos

El esquema `trazabilidad` contiene estas entidades principales:

- `trz_tabla_origen`: tablas registradas para auditoría.
- `trz_columna_origen`: columnas pertenecientes a cada tabla origen.
- `trz_tipo_operacion`: catálogo de operaciones admitidas.
- `trz_regla_auditoria`: operaciones habilitadas para una columna.
- `trz_evento`: evento por fila modificada, con contexto y snapshots.
- `trz_cambio_columna`: valores anterior y nuevo por columna que cambió.
- `trz_usuario`: referencia opcional al usuario PostgreSQL auditado.
- `trz_estacion`: catálogo de estaciones de trabajo.

`public.clientes_demo` es una tabla de ejemplo que se administra desde la interfaz. La configuración identifica tablas origen mediante esquema y nombre; por eso no existe una clave foránea física desde la configuración hacia cada tabla auditada.

## Instalación de la base de datos

Ejecuta los scripts en este orden. Usa DBeaver con una conexión activa a la base indicada en cada paso.

1. Conéctate a la base de mantenimiento `postgres` y ejecuta `00_crear_base.sql`. La creación de una base debe ejecutarse fuera de una transacción.
2. Conéctate a `control_cambios_db` y ejecuta `01_crear_schema.sql`, `02_esquema_tablas.sql`, `03_funciones.sql` y `04_permisos.sql`, en ese orden.
3. Con una cuenta autorizada, concede al usuario que administrará la configuración la membresía del rol administrativo. Cambia `cristop` por el nombre de tu rol PostgreSQL:

   ```sql
   GRANT autoaudit_admin TO cristop;
   ```

4. Ejecuta `05_configuracion_demo.sql`. Crea `public.clientes_demo`, sincroniza el diccionario, instala los triggers y habilita auditoría para `nombre`, `correo` y `ciudad` en las tres operaciones.
5. Ejecuta `06_consultas_historial.sql` para crear la vista y disponer de consultas de historial.
6. Ejecuta `07_pruebas_funcionales.sql`. Sus operaciones terminan con `ROLLBACK`, por lo que sirven para comprobar el registro sin conservar las filas de prueba.
7. Ejecuta los bloques de `08_pruebas_rendimiento.sql` por separado y conserva la salida de `EXPLAIN (ANALYZE, BUFFERS)`. Para el informe, repite cada tamaño de lote y documenta las mediciones.
8. Ejecuta `09_contexto_usuario_web.sql` y después `10_actualizar_funcion_usuario_web.sql` para registrar en la bitácora el usuario de la aplicación web.

### Advertencia sobre scripts destructivos

- `01_crear_schema.sql` elimina y vuelve a crear `trazabilidad` con `CASCADE`; se pierden las tablas y datos de ese esquema.
- `05_configuracion_demo.sql` elimina y vuelve a crear `public.clientes_demo` con `CASCADE`; se pierden los datos de esa tabla.
- Ejecuta esos scripts solo en una instalación limpia o de demostración. No los ejecutes sobre datos que debas conservar.
- `07` y `08` revierten sus cambios de prueba. Las secuencias de identidad pueden avanzar aunque se ejecute `ROLLBACK`.

## Instalación de la interfaz web en Ubuntu

Primero completa la instalación de la base de datos y verifica que `autoaudit_app` pueda conectarse a `control_cambios_db`. Los permisos de demostración para `public.clientes_demo` se conceden en `05_configuracion_demo.sql`.

Desde una terminal, entra a la carpeta `web` y prepara el entorno:

```bash
cd web
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

Edita `web/.env` con las credenciales de tu instalación. Configura la conexión y las cuentas web:

```ini
AUTOAUDIT_DB_HOST=127.0.0.1
AUTOAUDIT_DB_PORT=5432
AUTOAUDIT_DB_NAME=control_cambios_db
AUTOAUDIT_DB_USER=autoaudit_app
AUTOAUDIT_DB_PASSWORD=clave_de_postgresql

AUTOAUDIT_WEB_USER=admin
AUTOAUDIT_WEB_PASSWORD_HASH=hash_de_admin
AUTOAUDIT_WEB_CLIENT_USER=operador
AUTOAUDIT_WEB_CLIENT_PASSWORD_HASH=hash_de_operador
AUTOAUDIT_WEB_AUDITOR_USER=auditor
AUTOAUDIT_WEB_AUDITOR_PASSWORD_HASH=hash_de_auditor

FLASK_SECRET_KEY=clave_aleatoria_larga
AUTOAUDIT_OPEN_BROWSER=true
```

Genera un hash seguro para cada contraseña web. Ejecuta este comando una vez por cuenta y pega el resultado en la variable correspondiente:

```bash
python -c 'from getpass import getpass; from werkzeug.security import generate_password_hash; print(generate_password_hash(getpass("Contraseña: ")))'
```

Genera la clave de Flask con:

```bash
python -c 'import secrets; print(secrets.token_hex(32))'
```

Inicia la interfaz, desde la carpeta `web` y con el entorno virtual activo:

```bash
python app.py
```

En una VM Ubuntu sin escritorio, reenvía el puerto `5000` desde **Ports/Puertos** de VS Code y abre la dirección que VS Code proporciona. La aplicación escucha localmente en `127.0.0.1`; presiona `Ctrl+C` en la terminal para detenerla.

### Perfiles de la interfaz

| Perfil web | Acceso |
|---|---|
| `operador` | Clientes demo |
| `auditor` | Clientes demo e historial de control de cambios |
| `admin` | Clientes demo, historial y configuración de auditoría |

Estos perfiles pertenecen a la aplicación Flask, no son roles PostgreSQL separados. Todos usan la conexión configurada por `AUTOAUDIT_DB_USER`. El rol `autoaudit_admin` autoriza las operaciones de configuración de auditoría.

## Seguridad y publicación

- `web/.env` contiene contraseñas, hashes y una clave de sesión: **no lo publiques ni lo agregues a Git**.
- Publica `web/.env.example`, que contiene nombres de variables y valores de ejemplo. Quien descargue el proyecto debe copiarlo como `.env` y completar sus credenciales locales.
- No uses el superusuario de PostgreSQL como cuenta permanente de la aplicación.
- La cuenta de aplicación necesita solo los permisos requeridos sobre `clientes_demo` y para ejecutar las funciones administrativas autorizadas.
- Las rutas web validan el perfil y los formularios de cambios usan POST con protección CSRF. Las consultas de datos usan parámetros.
- Las cuentas web comparten el usuario PostgreSQL de la aplicación. El usuario web se guarda en `usuario_aplicacion_snapshot`; `usuario_snapshot` conserva el usuario de PostgreSQL.
- Esta aplicación está pensada para desarrollo y demostración local, no para publicarse directamente en Internet.

## Documentación adicional

- [README de la interfaz web](web/README.md): instrucciones específicas de configuración y ejecución.
- [Diagramas UML](UML/): diagramas del proyecto.
