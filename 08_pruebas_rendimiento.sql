-- AutoAudit: pruebas de rendimiento
--
-- Propósito:
--   Medir el tiempo de inserción de lotes crecientes en clientes_demo
--   con la auditoría activa y comparar 10,000 filas con el trigger desactivado.
--
-- Requisitos previos:
--   1. Ejecutar conectado a la base autoaudit_db.
--   2. Deben existir public.clientes_demo y el trigger trg_autoaudit_1.
--   3. La configuración de auditoría para public.clientes_demo debe estar activa.
--   4. La columna correo debe tener habilitada la operación insert.
--
-- Ejecución:
--   Ejecuta cada bloque BEGIN ... ROLLBACK por separado en DBeaver.
--   Conserva la salida completa de EXPLAIN (ANALYZE, BUFFERS).
--   Para el informe, repite cada tamaño al menos tres veces y reporta
--   mediana y rango. El tiempo puede variar por caché y actividad del servidor.
--
-- Nota:
--   ROLLBACK revierte las filas y eventos de auditoría de cada prueba.
--   Las secuencias de identidad de PostgreSQL pueden avanzar aunque se revierta
--   la transacción; esto es normal y no deja filas de prueba permanentes.


-- ================================================================
-- 0. Verificación de configuración y trigger
-- ================================================================

-- Debe mostrar correo / insert / true / true.
SELECT
    ta.esquema_origen,
    ta.nombre_tabla,
    ca.nombre_columna,
    ce.codigo_evento,
    ta.habilitada AS tabla_habilitada,
    ca.habilitada AS columna_habilitada,
    ce.habilitada AS evento_habilitado
FROM autoaudit.tabla_auditada AS ta
JOIN autoaudit.columna_auditada AS ca
  ON ca.tabla_auditada_id = ta.tabla_auditada_id
JOIN autoaudit.configuracion_evento AS ce
  ON ce.columna_auditada_id = ca.columna_auditada_id
WHERE ta.esquema_origen = 'public'
  AND ta.nombre_tabla = 'clientes_demo'
  AND ca.nombre_columna = 'correo'
  AND ce.codigo_evento = 'insert';

-- Debe mostrar trg_autoaudit_1 con tgenabled = 'O'.
-- Si el nombre del trigger es distinto, úsalo en la prueba sin auditoría.
SELECT
    t.tgname AS nombre_trigger,
    t.tgenabled AS estado
FROM pg_trigger AS t
WHERE t.tgrelid = 'public.clientes_demo'::regclass
  AND NOT t.tgisinternal;


-- ================================================================
-- 1. Inserción de 1,000 filas con auditoría activa
-- ================================================================

BEGIN;

EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO public.clientes_demo (nombre, correo, ciudad)
SELECT
    'Rendimiento 1000 ' || g,
    'rend-1000.' || txid_current() || '.' || g || '@example.com',
    'Guatemala'
FROM generate_series(1, 1000) AS g;

ROLLBACK;


-- ================================================================
-- 2. Inserción de 5,000 filas con auditoría activa
-- ================================================================

BEGIN;

EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO public.clientes_demo (nombre, correo, ciudad)
SELECT
    'Rendimiento 5000 ' || g,
    'rend-5000.' || txid_current() || '.' || g || '@example.com',
    'Guatemala'
FROM generate_series(1, 5000) AS g;

ROLLBACK;


-- ================================================================
-- 3. Inserción de 10,000 filas con auditoría activa
-- ================================================================

BEGIN;

EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO public.clientes_demo (nombre, correo, ciudad)
SELECT
    'Rendimiento 10000 ' || g,
    'rend-10000.' || txid_current() || '.' || g || '@example.com',
    'Guatemala'
FROM generate_series(1, 10000) AS g;

ROLLBACK;


-- ================================================================
-- 4. Comparación: 10,000 filas sin el trigger de auditoría
-- ================================================================
-- El trigger se desactiva dentro de la transacción. El ROLLBACK final
-- revierte tanto las filas como el cambio de estado del trigger, por lo que
-- el trigger vuelve a quedar habilitado al terminar este bloque.
-- Ejecuta este bloque después de las pruebas con auditoría activa.

BEGIN;

ALTER TABLE public.clientes_demo
    DISABLE TRIGGER trg_autoaudit_1;

EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO public.clientes_demo (nombre, correo, ciudad)
SELECT
    'Sin auditoria 10000 ' || g,
    'sin-audit-10000.' || txid_current() || '.' || g || '@example.com',
    'Guatemala'
FROM generate_series(1, 10000) AS g;

ROLLBACK;


-- ================================================================
-- 5. Verificación final: el trigger debe seguir habilitado
-- ================================================================

SELECT
    t.tgname AS nombre_trigger,
    t.tgenabled AS estado
FROM pg_trigger AS t
WHERE t.tgrelid = 'public.clientes_demo'::regclass
  AND NOT t.tgisinternal;

-- El estado esperado del trigger es 'O' (habilitado normalmente).
