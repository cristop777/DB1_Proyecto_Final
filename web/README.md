# Interfaz web de AutoAudit

Primera versión de la interfaz de administración y consulta, implementada con Flask, HTML y CSS. La aplicación se conecta a PostgreSQL y reutiliza las funciones y tablas del esquema `autoaudit`.

## Funciones disponibles

- Lista tablas y columnas visibles para el usuario configurado en PostgreSQL.
- Permite activar la auditoría por columna y operación (`insert`, `update`, `delete`).
- Permite desactivar la auditoría de una tabla al guardar una selección vacía.
- Sincroniza el diccionario de tablas y columnas.
- Consulta el historial por usuario, columna, esquema, tabla, operación y rango de fechas.
- Pagina el historial en grupos de 50 resultados y exporta los filtros actuales a CSV (máximo 10 000 filas por descarga).
- Protege las pantallas con una cuenta administrativa local y contraseña almacenada como hash.

## Requisitos previos

1. Instala PostgreSQL y crea la estructura de AutoAudit siguiendo el `README.md` de la carpeta principal.
2. Confirma que existe `public.clientes_demo` o alguna otra tabla de prueba.
3. Concede al usuario de conexión la membresía del rol administrador. Ejecuta esto con una cuenta autorizada, reemplazando `cristop` por tu usuario real:

   ```sql
   GRANT autoaudit_admin TO cristop;
   ```

4. El usuario también debe tener permisos para ver las tablas de origen que quiere configurar. PostgreSQL solo muestra en el diccionario las tablas que ese usuario puede ver.

## Instalación en Windows (PowerShell)

Abre PowerShell dentro de esta carpeta (`web`) y ejecuta:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
py -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Edita `.env` y completa `AUTOAUDIT_DB_USER`, `AUTOAUDIT_DB_PASSWORD`, `AUTOAUDIT_WEB_USER` y `FLASK_SECRET_KEY`. Genera un hash para la contraseña web dentro del entorno virtual:

```powershell
py -c "from getpass import getpass; from werkzeug.security import generate_password_hash; print(generate_password_hash(getpass('Contraseña web: ')))"
```

Copia el hash resultante en `AUTOAUDIT_WEB_PASSWORD_HASH` y después inicia la aplicación:

```powershell
py app.py
```

Abre `http://127.0.0.1:5000` en el navegador. Para detener el servidor, vuelve a PowerShell y presiona `Ctrl+C`.

## Instalación en Ubuntu

Desde esta carpeta, instala Python, crea un entorno virtual y ejecuta:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

Edita `.env` con las credenciales locales de PostgreSQL, el nombre de usuario web y una clave secreta propia. Genera el hash de la contraseña dentro del entorno virtual:

```bash
python -c 'from getpass import getpass; from werkzeug.security import generate_password_hash; print(generate_password_hash(getpass("Contraseña web: ")))'
```

Copia el hash resultante en `AUTOAUDIT_WEB_PASSWORD_HASH` y después inicia con:

```bash
python app.py
```

La aplicación intenta abrir el navegador automáticamente cuando Ubuntu tiene un escritorio gráfico. Si ejecutas VS Code conectado por SSH a una VM sin escritorio, el terminal indicará que debes reenviar el puerto `5000` desde la pestaña **Ports/Puertos** de VS Code y abrir la URL reenviada. La primera versión escucha únicamente en `127.0.0.1`, por lo que está pensada para uso local durante el desarrollo y la demostración.

## Seguridad y operación

- No subas `.env` ni escribas la contraseña en `app.py`. El `.gitignore` principal excluye estos archivos.
- Usa una cuenta de aplicación con los permisos mínimos necesarios; no uses el superusuario de PostgreSQL como configuración permanente.
- El inicio de sesión protege la interfaz; configura una cuenta y un hash únicos en `.env`. Mantén el servidor en `127.0.0.1`; no lo publiques en una red ni en Internet.
- El inicio de sesión restringe la administración web. Los eventos de datos siguen registrando el usuario PostgreSQL de la conexión que ejecutó la operación, por ejemplo `cristop` o `autoaudit_app`.
- La selección guardada sustituye el conjunto de operaciones activas de esa tabla. Guardar todo desmarcado desactiva sus triggers/configuración activa.
- La creación o modificación de triggers se realiza mediante las funciones PostgreSQL del proyecto. Si PostgreSQL niega la operación, revisa la membresía de `autoaudit_admin` y los permisos sobre la tabla de origen.

## Estructura

```text
web/
├── app.py
├── requirements.txt
├── .env.example
├── templates/
│   ├── base.html
│   ├── login.html
│   ├── index.html
│   ├── configure.html
│   ├── history.html
│   └── error.html
└── static/
    └── styles.css
```
