-- Crea el esquema únicamente si el editor está conectado
-- a la base control_cambios_db.
DO $$
BEGIN
    IF current_database() <> 'control_cambios_db' THEN
        RAISE EXCEPTION
            'Base incorrecta: conectado a %, se esperaba control_cambios_db',
            current_database();
    END IF;

    EXECUTE 'CREATE SCHEMA IF NOT EXISTS trazabilidad';
END
$$;


-- Define el esquema predeterminado para las conexiones nuevas.
ALTER DATABASE control_cambios_db
    SET search_path TO trazabilidad, public;

-- Define el esquema predeterminado para esta conexión.
SET search_path TO trazabilidad, public;


-- Verifica la base, el esquema activo y la ruta de búsqueda.
SELECT
    current_database() AS base,
    current_schema() AS esquema_actual,
    current_setting('search_path') AS ruta_busqueda;