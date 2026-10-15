-- Crea nuevamente el esquema para auditoría.
-- CASCADE elimina también las tablas, funciones, vistas y otros objetos
-- que existan dentro del esquema autoaudit.

DROP SCHEMA IF EXISTS autoaudit CASCADE;

CREATE SCHEMA autoaudit;

-- Define el esquema predeterminado para las conexiones nuevas
-- a esta base de datos.
ALTER DATABASE autoaudit_db
    SET search_path TO autoaudit, public;

-- Define el esquema predeterminado para esta conexión actual.
SET search_path TO autoaudit, public;