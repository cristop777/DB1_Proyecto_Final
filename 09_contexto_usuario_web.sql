-- Agrega a cada evento el usuario autenticado en la interfaz web.
-- Ejecuta conectado a control_cambios_db.
--
-- Este campo es distinto de usuario_snapshot:
-- usuario_snapshot conserva el usuario de PostgreSQL;
-- usuario_aplicacion_snapshot guardará el usuario de la aplicación web.

ALTER TABLE trazabilidad.trz_evento
ADD COLUMN IF NOT EXISTS usuario_aplicacion_snapshot text;

-- Comprueba que la columna exista.
SELECT
    table_schema,
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'trazabilidad'
  AND table_name = 'trz_evento'
  AND column_name = 'usuario_aplicacion_snapshot';