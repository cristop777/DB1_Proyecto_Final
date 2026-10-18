# Auto Auditoría: interfaz web

Interfaz local para gestionar una tabla de demostración, configurar la auditoría y consultar el historial de cambios. Está desarrollada con Flask, HTML y CSS, y se conecta a PostgreSQL mediante la cuenta técnica `autoaudit_app`.

La aplicación usa la base de datos `control_cambios_db` y el esquema `trazabilidad`.

## Funciones

- Gestiona registros de `public.clientes_demo`: alta, consulta, edición y eliminación.
- Audita los cambios de las columnas `nombre`, `correo` y `ciudad`.
- Configura columnas y operaciones auditadas para las tablas visibles a la cuenta PostgreSQL de la aplicación.
- Sincroniza las tablas y columnas disponibles desde el diccionario de PostgreSQL.
- Consulta el historial por usuario, columna, esquema, tabla, operación y fechas.
- Pagina los resultados y permite exportar hasta 10 000 filas a CSV.
- Identifica los cambios realizados desde la web con el usuario que inició sesión, además de conservar el usuario PostgreSQL de la conexión.
- Protege las rutas con inicio de sesión, tokens CSRF en formularios y perfiles de acceso.

## Perfiles web

Los perfiles se configuran en `web/.env`. No son cuentas independientes de PostgreSQL: todos se conectan mediante `AUTOAUDIT_DB_USER`.

| Perfil | Acceso |
|---|---|
| `operador` | Clientes demo |
| `auditor` | Clientes demo e historial de control de cambios |
| `admin` | Clientes demo, historial y configuración de auditoría |

La cuenta administradora necesita pertenecer al rol PostgreSQL `autoaudit_admin` para usar la configuración. Los permisos para operar `clientes_demo` se conceden en `05_configuracion_demo.sql`.

## Requisitos previos

1. Instala PostgreSQL y prepara `control_cambios_db` ejecutando los scripts SQL del proyecto en el orden documentado en el README principal.
2. Crea `public.clientes_demo` y habilita sus columnas auditadas mediante `05_configuracion_demo.sql`.
3. Concede al usuario PostgreSQL de la aplicación la membresía administrativa, si usará las pantallas de configuración. Ejecuta con una cuenta autorizada y reemplaza `cristop` por el rol PostgreSQL correspondiente:

   ```sql
   GRANT autoaudit_admin TO cristop;
   ```

4. Para registrar quién inició sesión en la web, aplica también las actualizaciones `09_contexto_usuario_web.sql` y `10_actualizar_funcion_usuario_web.sql`, después de crear las tablas y funciones base.

## Instalación en Ubuntu

Desde una terminal en la carpeta `web`:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

Edita `.env` y configura la conexión de PostgreSQL y las cuentas web:

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

Genera un hash seguro para cada contraseña web, ejecutando el comando por separado para cada cuenta:

```bash
python -c 'from getpass import getpass; from werkzeug.security import generate_password_hash; print(generate_password_hash(getpass("Contraseña: ")))'
```

Genera la clave de sesión de Flask:

```bash
python -c 'import secrets; print(secrets.token_hex(32))'
```

Pega cada resultado en la variable correspondiente de `.env`. No pongas las contraseñas web en texto plano.

## Iniciar la aplicación

Con el entorno virtual activo y desde la carpeta `web`:

```bash
python app.py
```

Si ejecutas VS Code conectado por SSH a una VM sin escritorio gráfico, reenvía el puerto `5000` desde la pestaña **Ports/Puertos** y abre la dirección que muestre VS Code. La aplicación escucha en `127.0.0.1` para la demostración local. Para detenerla, presiona `Ctrl+C` en la terminal.

## Seguridad y operación

- No subas `web/.env` al repositorio. El archivo contiene credenciales; solo se debe subir `.env.example` con valores de ejemplo.
- No uses el superusuario de PostgreSQL como cuenta de conexión de la aplicación.
- La cuenta `autoaudit_app` necesita permisos de lectura y escritura sobre `public.clientes_demo`, además de los permisos de lectura y configuración que requieran sus funciones.
- Los formularios de cambios usan POST y protección CSRF. Los valores SQL se envían como parámetros.
- Los roles de la web limitan las rutas disponibles, pero comparten la conexión PostgreSQL de `autoaudit_app`. El perfil web se registra como contexto de auditoría; `usuario_snapshot` conserva el usuario PostgreSQL.
- La tabla de bitácora no debe modificarse directamente desde la interfaz.

## Estructura

```text
web/
├── app.py
├── requirements.txt
├── .env.example
├── README.md
├── templates/
│   ├── base.html
│   ├── login.html
│   ├── index.html
│   ├── configure.html
│   ├── clientes.html
│   ├── editar_cliente.html
│   ├── history.html
│   └── error.html
└── static/
    └── styles.css
```
