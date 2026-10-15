--Realiza las pruebas funcionales
BEGIN;

-- INSERT
INSERT INTO public.clientes_demo (nombre, correo, ciudad)
VALUES (
    'Prueba AutoAudit',
    'prueba.' || txid_current() || '@example.com',
    'Guatemala'
);

-- UPDATE
UPDATE public.clientes_demo
SET correo = 'actualizada.' || txid_current() || '@example.com'
WHERE correo = 'prueba.' || txid_current() || '@example.com';

-- DELETE
DELETE FROM public.clientes_demo
WHERE correo = 'actualizada.' || txid_current() || '@example.com';

-- Deben aparecer los tres eventos de prueba.
SELECT
    fecha_evento,
    operacion,
    usuario,
    columna,
    valor_anterior,
    valor_nuevo
FROM autoaudit.v_historial_detallado
WHERE columna = 'correo'
  AND (
      valor_anterior #>> '{}' LIKE 'prueba.%@example.com'
      OR valor_nuevo #>> '{}' LIKE 'prueba.%@example.com'
      OR valor_anterior #>> '{}' LIKE 'actualizada.%@example.com'
      OR valor_nuevo #>> '{}' LIKE 'actualizada.%@example.com'
  )
ORDER BY fecha_evento;

ROLLBACK;