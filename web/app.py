"""Interfaz web local para configurar y consultar AutoAudit."""

import hmac
import csv
import io
import json
import os
import secrets
import threading
import webbrowser
from datetime import date, timedelta
from functools import wraps

import psycopg
from dotenv import load_dotenv
from flask import (
    Flask,
    abort,
    flash,
    make_response,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from psycopg.rows import dict_row
from werkzeug.security import check_password_hash

load_dotenv()

app = Flask(__name__)
app.config["SECRET_KEY"] = os.getenv("FLASK_SECRET_KEY") or secrets.token_hex(32)
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

EVENTS = {"insert", "update", "delete"}
HISTORY_FROM = """
    FROM trazabilidad.trz_evento AS e
    JOIN trazabilidad.trz_tabla_origen AS ta
      ON ta.tabla_auditada_id = e.tabla_auditada_id
    JOIN trazabilidad.trz_cambio_columna AS d
      ON d.evento_auditoria_id = e.evento_auditoria_id
"""


def set_web_user_context(conn):
    """Pasa el usuario autenticado al trigger durante esta transacción."""
    conn.execute(
        "SELECT set_config('trazabilidad.usuario_aplicacion', %s, true)",
        (session["web_user"],),
    )


def db_connection():
    """Abre una conexión usando variables de entorno, sin guardar claves en código."""
    return psycopg.connect(
        host=os.getenv("AUTOAUDIT_DB_HOST", "127.0.0.1"),
        port=os.getenv("AUTOAUDIT_DB_PORT", "5432"),
        dbname=os.getenv("AUTOAUDIT_DB_NAME", "control_cambios_db"),
        user=os.getenv("AUTOAUDIT_DB_USER", ""),
        password=os.getenv("AUTOAUDIT_DB_PASSWORD", ""),
        row_factory=dict_row,
        connect_timeout=5,
    )


def csrf_protected(view):
    """Protección CSRF pequeña para los formularios de esta interfaz local."""

    @wraps(view)
    def wrapped(*args, **kwargs):
        if request.method == "POST":
            submitted = request.form.get("csrf_token", "")
            expected = session.get("csrf_token", "")
            if not expected or not hmac.compare_digest(submitted, expected):
                abort(
                    400,
                    description="La sesión del formulario venció. Recarga la página.",
                )
        if "csrf_token" not in session:
            session["csrf_token"] = secrets.token_urlsafe(32)
        return view(*args, **kwargs)

    return wrapped


def login_required(view):
    """Restringe las funciones de administración a la sesión autenticada."""

    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("web_user"):
            return redirect(url_for("login"))
        return view(*args, **kwargs)

    return wrapped


def roles_required(*allowed_roles):
    """Restringe una ruta a perfiles web autorizados."""
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not session.get("web_user"):
                return redirect(url_for("login"))
            if session.get("web_role") not in allowed_roles:
                flash("Tu perfil no tiene acceso a esa sección.", "warning")
                return redirect(url_for("clients"))
            return view(*args, **kwargs)
        return wrapped
    return decorator


def configured_web_accounts():
    """Devuelve las cuentas web configuradas y el perfil de cada una."""
    account_settings = (
        ("AUTOAUDIT_WEB_USER", "AUTOAUDIT_WEB_PASSWORD_HASH", "admin"),
        ("AUTOAUDIT_WEB_CLIENT_USER", "AUTOAUDIT_WEB_CLIENT_PASSWORD_HASH", "operador"),
        ("AUTOAUDIT_WEB_AUDITOR_USER", "AUTOAUDIT_WEB_AUDITOR_PASSWORD_HASH", "auditor"),
    )
    accounts = []
    for user_key, hash_key, role in account_settings:
        username = os.getenv(user_key, "").strip()
        password_hash = os.getenv(hash_key, "").strip()
        if username and password_hash:
            accounts.append({"username": username, "password_hash": password_hash, "role": role})
    return accounts


@app.context_processor
def inject_csrf_token():
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)
    return {"csrf_token": session["csrf_token"]}


@app.route("/login", methods=["GET", "POST"])
@csrf_protected
def login():
    if session.get("web_user"):
        return redirect(url_for("clients"))

    if request.method == "POST":
        accounts = configured_web_accounts()
        submitted_user = request.form.get("usuario", "").strip()
        submitted_password = request.form.get("contrasena", "")

        matched_account = None
        for account in accounts:
            try:
                password_matches = check_password_hash(
                    account["password_hash"], submitted_password
                )
            except (ValueError, TypeError):
                password_matches = False
            if hmac.compare_digest(submitted_user, account["username"]) and password_matches:
                matched_account = account
                break

        if not accounts:
            flash("Configura al menos una cuenta web y su hash de contraseña en .env.", "danger")
        elif matched_account:
            session.clear()
            session["web_user"] = matched_account["username"]
            session["web_role"] = matched_account["role"]
            flash("Sesión iniciada.", "success")
            return redirect(url_for("clients"))
        else:
            flash("Usuario o contraseña incorrectos.", "danger")

    return render_template("login.html")


@app.post("/logout")
@login_required
@csrf_protected
def logout():
    session.clear()
    flash("Sesión cerrada.", "success")
    return redirect(url_for("login"))


@app.route("/clientes", methods=["GET", "POST"])
@login_required
@csrf_protected
def clients():
    """Muestra clientes demo y permite crear registros auditables."""
    if request.method == "POST":
        nombre = request.form.get("nombre", "").strip()
        correo = request.form.get("correo", "").strip()
        ciudad = request.form.get("ciudad", "").strip() or None
        if not nombre or not correo:
            flash("Nombre y correo son obligatorios.", "warning")
            return redirect(url_for("clients"))
        try:
            with db_connection() as conn:
                set_web_user_context(conn)
                conn.execute(
                    """INSERT INTO public.clientes_demo (nombre, correo, ciudad)
                       VALUES (%s, %s, %s)""",
                    (nombre, correo, ciudad),
                )
            flash("Cliente creado y registrado en el historial.", "success")
            return redirect(url_for("clients"))
        except psycopg.errors.UniqueViolation:
            flash("Ya existe un cliente con ese correo.", "danger")
        except psycopg.Error as exc:
            flash(database_error_message(exc), "danger")

    try:
        with db_connection() as conn:
            rows = conn.execute(
                """SELECT id, nombre, correo, ciudad
                   FROM public.clientes_demo
                   ORDER BY id DESC
                   LIMIT 500"""
            ).fetchall()
        return render_template("clientes.html", clients=rows)
    except psycopg.Error as exc:
        return render_template("error.html", message=database_error_message(exc)), 500


@app.route("/clientes/<int:client_id>/editar", methods=["GET", "POST"])
@login_required
@csrf_protected
def edit_client(client_id):
    """Edita un cliente; el trigger registra las columnas que cambiaron."""
    try:
        if request.method == "POST":
            nombre = request.form.get("nombre", "").strip()
            correo = request.form.get("correo", "").strip()
            ciudad = request.form.get("ciudad", "").strip() or None
            if not nombre or not correo:
                flash("Nombre y correo son obligatorios.", "warning")
                return redirect(url_for("edit_client", client_id=client_id))
            with db_connection() as conn:
                set_web_user_context(conn)
                result = conn.execute(
                    """UPDATE public.clientes_demo
                       SET nombre = %s, correo = %s, ciudad = %s
                       WHERE id = %s""",
                    (nombre, correo, ciudad, client_id),
                )
            if result.rowcount == 0:
                abort(404, description="No se encontró el cliente solicitado.")
            flash("Cliente actualizado y cambios enviados al historial.", "success")
            return redirect(url_for("clients"))

        with db_connection() as conn:
            row = conn.execute(
                """SELECT id, nombre, correo, ciudad
                   FROM public.clientes_demo WHERE id = %s""",
                (client_id,),
            ).fetchone()
        if row is None:
            abort(404, description="No se encontró el cliente solicitado.")
        return render_template("editar_cliente.html", client=row)
    except psycopg.errors.UniqueViolation:
        flash("Ya existe un cliente con ese correo.", "danger")
        return redirect(url_for("edit_client", client_id=client_id))
    except psycopg.Error as exc:
        return render_template("error.html", message=database_error_message(exc)), 500


@app.post("/clientes/<int:client_id>/eliminar")
@login_required
@csrf_protected
def delete_client(client_id):
    """Elimina un cliente mediante POST y registra la operación."""
    try:
        with db_connection() as conn:
            set_web_user_context(conn)
            result = conn.execute(
                "DELETE FROM public.clientes_demo WHERE id = %s",
                (client_id,),
            )
        if result.rowcount == 0:
            flash("El cliente ya no existe.", "warning")
        else:
            flash("Cliente eliminado y registrado en el historial.", "success")
    except psycopg.Error as exc:
        flash(database_error_message(exc), "danger")
    return redirect(url_for("clients"))


def list_tables():
    """Obtiene tablas visibles para el usuario PostgreSQL de la aplicación."""
    query = """
        SELECT t.table_schema AS esquema,
               t.table_name AS tabla,
               COALESCE(ta.habilitada, false) AS habilitada,
               COUNT(c.column_name)::integer AS total_columnas
        FROM information_schema.tables AS t
        LEFT JOIN trazabilidad.trz_tabla_origen AS ta
          ON ta.esquema_origen::text = t.table_schema
         AND ta.nombre_tabla::text = t.table_name
        LEFT JOIN information_schema.columns AS c
          ON c.table_schema = t.table_schema
         AND c.table_name = t.table_name
        WHERE t.table_type = 'BASE TABLE'
          AND t.table_schema NOT IN ('information_schema', 'trazabilidad')
          AND left(t.table_schema, 3) <> 'pg_'
        GROUP BY t.table_schema, t.table_name, ta.habilitada
        ORDER BY t.table_schema, t.table_name
    """
    with db_connection() as conn:
        return conn.execute(query).fetchall()


def get_table_config(schema, table):
    """Lee columnas disponibles y la configuración actual de una tabla."""
    query = """
        SELECT c.column_name AS columna,
               c.data_type AS tipo_dato,
               c.ordinal_position AS posicion,
               COALESCE(ca.habilitada, false) AS habilitada,
               COALESCE(
                   array_agg(ce.codigo_evento ORDER BY ce.codigo_evento)
                       FILTER (WHERE ce.habilitada),
                   ARRAY[]::text[]
               ) AS operaciones
        FROM information_schema.columns AS c
        LEFT JOIN trazabilidad.trz_tabla_origen AS ta
          ON ta.esquema_origen::text = c.table_schema
         AND ta.nombre_tabla::text = c.table_name
        LEFT JOIN trazabilidad.trz_columna_origen AS ca
          ON ca.tabla_auditada_id = ta.tabla_auditada_id
         AND ca.nombre_columna::text = c.column_name
        LEFT JOIN trazabilidad.trz_regla_auditoria AS ce
          ON ce.columna_auditada_id = ca.columna_auditada_id
        WHERE c.table_schema = %s AND c.table_name = %s
        GROUP BY c.column_name, c.data_type, c.ordinal_position, ca.habilitada
        ORDER BY c.ordinal_position
    """
    with db_connection() as conn:
        columns = conn.execute(query, (schema, table)).fetchall()
    if not columns:
        abort(404, description="La tabla no existe o no es visible para este usuario.")
    return columns


@app.get("/")
@login_required
@roles_required("admin")
def index():
    try:
        tables = list_tables()
        return render_template("index.html", tables=tables)
    except psycopg.Error as exc:
        return render_template("error.html", message=database_error_message(exc)), 500


@app.route("/configurar", methods=["GET", "POST"])
@login_required
@roles_required("admin")
@csrf_protected
def configure():
    schema = request.values.get("esquema", "")
    table = request.values.get("tabla", "")
    if not schema or not table:
        flash("Selecciona un esquema y una tabla.", "warning")
        return redirect(url_for("index"))

    try:
        columns = get_table_config(schema, table)
        if request.method == "POST":
            selected = []
            for column in columns:
                operations = set(request.form.getlist(f"op:{column['columna']}"))
                if operations - EVENTS:
                    abort(400, description="Se recibió una operación no válida.")
                if operations:
                    selected.append((column["columna"], sorted(operations)))

            with db_connection() as conn:
                existing = conn.execute(
                    """SELECT habilitada FROM trazabilidad.trz_tabla_origen
                       WHERE esquema_origen = %s::name AND nombre_tabla = %s::name""",
                    (schema, table),
                ).fetchone()

                # Deshabilita la configuración anterior y vuelve a aplicar
                # exactamente las columnas y operaciones marcadas en el formulario.
                if existing:
                    conn.execute(
                        "SELECT trazabilidad.trz_desactivar_tabla(%s::name, %s::name)",
                        (schema, table),
                    )

                for column, operations in selected:
                    conn.execute(
                        """SELECT trazabilidad.trz_configurar_columna(
                               %s::name, %s::name, %s::name, %s::text[]
                           )""",
                        (schema, table, column, operations),
                    )

            if selected:
                flash(
                    f"Auditoría aplicada a {len(selected)} columna(s) "
                    f"de {schema}.{table}.",
                    "success",
                )
            else:
                flash(f"Auditoría desactivada para {schema}.{table}.", "success")
            return redirect(url_for("configure", esquema=schema, tabla=table))

        return render_template(
            "configure.html",
            schema=schema,
            table=table,
            columns=columns,
        )
    except psycopg.Error as exc:
        return render_template("error.html", message=database_error_message(exc)), 500


@app.post("/sincronizar")
@login_required
@roles_required("admin")
@csrf_protected
def synchronize():
    try:
        with db_connection() as conn:
            conn.execute("SELECT trazabilidad.trz_sincronizar_diccionario()")
        flash(
            "El diccionario de tablas y columnas se sincronizó correctamente.",
            "success",
        )
    except psycopg.Error as exc:
        flash(database_error_message(exc), "danger")
    return redirect(url_for("index"))


@app.get("/historial")
@login_required
@roles_required("admin", "auditor")
def history():
    filters, conditions, params = read_history_filters()
    page = max(request.args.get("pagina", 1, type=int), 1)
    page_size = 50

    try:
        where_sql = " AND ".join(conditions) if conditions else "TRUE"
        with db_connection() as conn:
            total = conn.execute(
                f"SELECT count(*) AS total {HISTORY_FROM} WHERE {where_sql}",
                params,
            ).fetchone()["total"]

            pages = max((total + page_size - 1) // page_size, 1)
            page = min(page, pages)
            query = f"""
                SELECT e.evento_auditoria_id, e.fecha_evento,
                       ta.esquema_origen::text AS esquema,
                       ta.nombre_tabla::text AS tabla,
                       e.codigo_evento AS operacion,
                       COALESCE(e.usuario_aplicacion_snapshot,
                                e.usuario_snapshot::text) AS usuario,
                       e.estacion_snapshot AS estacion,
                       e.direccion_ip::text AS direccion_ip,
                       e.clave_fila,
                       d.nombre_columna_snapshot::text AS columna,
                       d.valor_anterior, d.valor_nuevo
                {HISTORY_FROM}
                WHERE {where_sql}
                ORDER BY e.fecha_evento DESC, e.evento_auditoria_id DESC,
                         d.detalle_auditoria_id DESC
                LIMIT %s OFFSET %s
            """
            rows = conn.execute(
                query,
                [*params, page_size, (page - 1) * page_size],
            ).fetchall()

        return render_template(
            "history.html",
            rows=rows,
            filters=filters,
            page=page,
            pages=pages,
            total=total,
        )
    except psycopg.Error as exc:
        return render_template("error.html", message=database_error_message(exc)), 500


def read_history_filters():
    """Valida los filtros compartidos por la consulta y la exportación."""
    filters = {
        "usuario": request.args.get("usuario", "").strip(),
        "columna": request.args.get("columna", "").strip(),
        "esquema": request.args.get("esquema", "").strip(),
        "tabla": request.args.get("tabla", "").strip(),
        "operacion": request.args.get("operacion", "").strip().lower(),
        "desde": request.args.get("desde", "").strip(),
        "hasta": request.args.get("hasta", "").strip(),
    }
    if filters["operacion"] and filters["operacion"] not in EVENTS:
        abort(400, description="Operación no válida para el filtro.")

    conditions = []
    params = []
    for key, sql_expression in (
        ("usuario", "COALESCE(e.usuario_aplicacion_snapshot, e.usuario_snapshot::text)"),
        ("columna", "d.nombre_columna_snapshot::text"),
        ("esquema", "ta.esquema_origen::text"),
        ("tabla", "ta.nombre_tabla::text"),
        ("operacion", "e.codigo_evento"),
    ):
        if filters[key]:
            conditions.append(f"{sql_expression} = %s")
            params.append(filters[key])

    try:
        if filters["desde"]:
            start_date = date.fromisoformat(filters["desde"])
            conditions.append("e.fecha_evento >= %s")
            params.append(start_date)

        if filters["hasta"]:
            end_date = date.fromisoformat(filters["hasta"]) + timedelta(days=1)
            conditions.append("e.fecha_evento < %s")
            params.append(end_date)
    except ValueError:
        abort(400, description="Las fechas deben tener el formato AAAA-MM-DD.")

    if filters["desde"] and filters["hasta"] and filters["desde"] > filters["hasta"]:
        abort(
            400, description="La fecha inicial no puede ser posterior a la fecha final."
        )

    return filters, conditions, params


@app.get("/historial/exportar.csv")
@login_required
@roles_required("admin", "auditor")
def export_history():
    filters, conditions, params = read_history_filters()
    where_sql = " AND ".join(conditions) if conditions else "TRUE"
    query = f"""
        SELECT e.evento_auditoria_id, e.fecha_evento,
               ta.esquema_origen::text AS esquema,
               ta.nombre_tabla::text AS tabla,
               e.clave_fila,
               e.codigo_evento AS operacion,
               COALESCE(e.usuario_aplicacion_snapshot,
                        e.usuario_snapshot::text) AS usuario,
               e.estacion_snapshot AS estacion,
               e.direccion_ip::text AS direccion_ip,
               d.nombre_columna_snapshot::text AS columna,
               d.valor_anterior, d.valor_nuevo
        {HISTORY_FROM}
        WHERE {where_sql}
        ORDER BY e.fecha_evento DESC, e.evento_auditoria_id DESC,
                 d.detalle_auditoria_id DESC
        LIMIT 10000
    """

    try:
        with db_connection() as conn:
            rows = conn.execute(query, params).fetchall()
    except psycopg.Error as exc:
        return render_template("error.html", message=database_error_message(exc)), 500

    output = io.StringIO(newline="")
    output.write("\ufeff")  # Ayuda a Excel a reconocer los acentos en UTF-8.
    writer = csv.writer(output)
    writer.writerow(
        [
            "evento_id",
            "fecha",
            "esquema",
            "tabla",
            "clave_fila",
            "operacion",
            "usuario",
            "estacion",
            "direccion_ip",
            "columna",
            "valor_anterior",
            "valor_nuevo",
        ]
    )

    for row in rows:
        writer.writerow(
            [
                row["evento_auditoria_id"],
                row["fecha_evento"].isoformat(),
                row["esquema"],
                row["tabla"],
                json_csv_value(row["clave_fila"]),
                row["operacion"],
                row["usuario"],
                row["estacion"],
                row["direccion_ip"],
                row["columna"],
                json_csv_value(row["valor_anterior"]),
                json_csv_value(row["valor_nuevo"]),
            ]
        )

    response = make_response(output.getvalue())
    response.headers["Content-Type"] = "text/csv; charset=utf-8"
    response.headers["Content-Disposition"] = (
        f"attachment; filename=autoaudit_historial_{date.today():%Y%m%d}.csv"
    )
    return response


def json_csv_value(value):
    """Convierte valores JSON a CSV y neutraliza prefijos de fórmulas."""
    if value is None:
        return ""

    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False, default=str)

    text = str(value)
    if text.startswith(("=", "+", "-", "@", "\t", "\r")):
        return "'" + text

    return text


def database_error_message(exc):
    """Traduce errores comunes de configuración a instrucciones entendibles."""
    text = str(exc).splitlines()[0] if str(exc) else "Error de base de datos."

    if "permission denied" in text.lower() or "privilege" in text.lower():
        return (
            f"PostgreSQL rechazó la operación: {text} Comprueba que el usuario de la "
            "aplicación sea miembro de autoaudit_admin y tenga acceso a las tablas origen."
        )

    if "connection" in text.lower() or "connect" in text.lower():
        return (
            f"No se pudo conectar con PostgreSQL: {text} "
            "Revisa el archivo .env y que el servidor esté activo."
        )

    return f"PostgreSQL informó: {text}"


if __name__ == "__main__":
    # La aplicación queda disponible solo en el equipo local durante esta primera versión.
    open_browser = os.getenv("AUTOAUDIT_OPEN_BROWSER", "true").lower() not in {
        "0",
        "false",
        "no",
        "off",
    }
    browser_url = "http://127.0.0.1:5000"

    if open_browser and (os.getenv("DISPLAY") or os.getenv("WAYLAND_DISPLAY")):
        # Espera un momento para que Flask esté listo antes de abrir el navegador.
        threading.Timer(1.2, lambda: webbrowser.open(browser_url)).start()
    elif open_browser:
        print(
            "Entorno sin navegador gráfico local. En VS Code, reenvía el puerto "
            "5000 desde la pestaña Ports/Puertos y abre la URL que aparece."
        )

    app.run(host="127.0.0.1", port=5000, debug=False)
