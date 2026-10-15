--Crea las vistas para los historiales
CREATE OR REPLACE VIEW autoaudit.v_historial_detallado AS
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
FROM autoaudit.evento_auditoria AS e
JOIN autoaudit.detalle_auditoria AS d
    ON d.evento_auditoria_id = e.evento_auditoria_id;

GRANT SELECT ON autoaudit.v_historial_detallado TO autoaudit_admin;

-- Historial por usuario y columna
SELECT *
FROM autoaudit.v_historial_detallado
WHERE usuario = 'cristop'
  AND columna = 'correo'
ORDER BY fecha_evento DESC;

-- Historial de una columna, sin filtrar por usuario
SELECT *
FROM autoaudit.v_historial_detallado
WHERE columna = 'correo'
ORDER BY fecha_evento DESC;

-- Eventos de hoy según la zona horaria de la sesión
SELECT *
FROM autoaudit.v_historial_detallado
WHERE fecha_evento >= CURRENT_DATE::timestamptz
  AND fecha_evento < (CURRENT_DATE + 1)::timestamptz
ORDER BY fecha_evento DESC;