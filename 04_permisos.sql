--Crea los permisos para auditoria
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
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

GRANT USAGE ON SCHEMA autoaudit TO autoaudit_admin;

GRANT SELECT
ON ALL TABLES IN SCHEMA autoaudit
TO autoaudit_admin;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE
ON ALL TABLES IN SCHEMA autoaudit
FROM autoaudit_admin;

REVOKE ALL
ON FUNCTION autoaudit.sincronizar_diccionario()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION autoaudit.configurar_columna(name, name, name, text[])
FROM PUBLIC;

REVOKE ALL
ON FUNCTION autoaudit.desactivar_operacion(name, name, name, text)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION autoaudit.desactivar_tabla(name, name)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION autoaudit.sincronizar_diccionario()
TO autoaudit_admin;

GRANT EXECUTE
ON FUNCTION autoaudit.configurar_columna(name, name, name, text[])
TO autoaudit_admin;

GRANT EXECUTE
ON FUNCTION autoaudit.desactivar_operacion(name, name, name, text)
TO autoaudit_admin;

GRANT EXECUTE
ON FUNCTION autoaudit.desactivar_tabla(name, name)
TO autoaudit_admin;