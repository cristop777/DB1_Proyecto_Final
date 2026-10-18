-- Realiza pruebas funcionales de auditoría.
-- Ejecuta este archivo conectado a control_cambios_db,
-- después de configurar public.clientes_demo con el script 05.

BEGIN;


-- Prueba INSERT.
INSERT INTO public.clientes_demo (nombre, correo, ciudad)
VALUES (
    'Prueba AutoAudit',
    'prueba.' || txid_current() || '@example.com',
    'Guatemala'
);


-- Prueba UPDATE.
UPDATE public.clientes_demo
SET correo = 'actualizada.' || txid_current() || '@example.com'
WHERE correo = 'prueba.' || txid_current() || '@example.com';


-- Prueba DELETE.
DELETE FROM public.clientes_demo
WHERE correo = 'actualizada.' || txid_current() || '@example.com';


-- Deben aparecer los tres eventos de prueba en el historial.
SELECT
    fecha_evento,
    operacion,
    usuario,
    columna,
    valor_anterior,
    valor_nuevo
FROM trazabilidad.v_trz_historial_detallado
WHERE columna = 'correo'
  AND (
      valor_anterior #>> '{}' LIKE 'prueba.%@example.com'
      OR valor_nuevo #>> '{}' LIKE 'prueba.%@example.com'
      OR valor_anterior #>> '{}' LIKE 'actualizada.%@example.com'
      OR valor_nuevo #>> '{}' LIKE 'actualizada.%@example.com'
  )
ORDER BY fecha_evento;


-- Revierte las filas y eventos temporales generados por esta prueba.
ROLLBACK;