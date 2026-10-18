-- Crea la vista y las consultas para revisar el historial de trazabilidad.
-- Ejecuta este archivo conectado a control_cambios_db,
-- después de crear las tablas y funciones del sistema.

-- Vista detallada de cambios por columna.
CREATE OR REPLACE VIEW trazabilidad.v_trz_historial_detallado AS
SELECT
    e.evento_auditoria_id,
    e.fecha_evento,
    e.codigo_evento AS operacion,
    e.usuario_snapshot AS usuario,
    e.estacion_snapshot AS estacion,
    e.direccion_ip,
    e.clave_fila,
    d.nombre_columna_snapshot AS columna,
    d.valor_anterior,
    d.valor_nuevo
FROM trazabilidad.trz_evento AS e
JOIN trazabilidad.trz_cambio_columna AS d
    ON d.evento_auditoria_id = e.evento_auditoria_id;


-- Permite que el rol administrativo consulte la vista.
GRANT SELECT
ON trazabilidad.v_trz_historial_detallado
TO autoaudit_admin;


-- Historial por usuario y columna.
SELECT *
FROM trazabilidad.v_trz_historial_detallado
WHERE usuario = 'cristop'
  AND columna = 'correo'
ORDER BY fecha_evento DESC;


-- Historial de una columna, sin filtrar por usuario.
SELECT *
FROM trazabilidad.v_trz_historial_detallado
WHERE columna = 'correo'
ORDER BY fecha_evento DESC;


-- Eventos de hoy, según la zona horaria de la sesión.
SELECT *
FROM trazabilidad.v_trz_historial_detallado
WHERE fecha_evento >= CURRENT_DATE::timestamptz
  AND fecha_evento < (CURRENT_DATE + 1)::timestamptz
ORDER BY fecha_evento DESC;