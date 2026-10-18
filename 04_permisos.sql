-- Configura los permisos administrativos del sistema de trazabilidad.
-- Ejecuta este archivo conectado a control_cambios_db.

-- Crea el rol administrativo si todavía no existe.
-- Es un rol grupal: no permite iniciar sesión directamente.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'autoaudit_admin'
    ) THEN
        CREATE ROLE autoaudit_admin
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE;
    END IF;
END
$$;

-- Permite al rol administrativo acceder al esquema de trazabilidad.
GRANT USAGE
ON SCHEMA trazabilidad
TO autoaudit_admin;

-- Permite consultar las tablas y vistas del sistema.
GRANT SELECT
ON ALL TABLES IN SCHEMA trazabilidad
TO autoaudit_admin;

-- Evita que se modifique directamente la bitácora y la configuración.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE
ON ALL TABLES IN SCHEMA trazabilidad
FROM autoaudit_admin;

-- Revoca el acceso público a las funciones de configuración.
REVOKE ALL
ON FUNCTION trazabilidad.trz_sincronizar_diccionario()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION trazabilidad.trz_configurar_columna(
    name,
    name,
    name,
    text[]
)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION trazabilidad.trz_desactivar_operacion(
    name,
    name,
    name,
    text
)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION trazabilidad.trz_desactivar_tabla(
    name,
    name
)
FROM PUBLIC;

-- Solo el rol administrativo puede ejecutar las funciones de configuración.
GRANT EXECUTE
ON FUNCTION trazabilidad.trz_sincronizar_diccionario()
TO autoaudit_admin;

GRANT EXECUTE
ON FUNCTION trazabilidad.trz_configurar_columna(
    name,
    name,
    name,
    text[]
)
TO autoaudit_admin;

GRANT EXECUTE
ON FUNCTION trazabilidad.trz_desactivar_operacion(
    name,
    name,
    name,
    text
)
TO autoaudit_admin;

GRANT EXECUTE
ON FUNCTION trazabilidad.trz_desactivar_tabla(
    name,
    name
)
TO autoaudit_admin;