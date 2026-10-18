-- Actualiza la función de auditoría para conservar también
-- el usuario autenticado en la aplicación web.
--
-- La aplicación deberá establecer el valor de sesión
-- trazabilidad.usuario_aplicacion antes de cada INSERT, UPDATE o DELETE.
-- usuario_snapshot seguirá guardando el usuario de PostgreSQL.

CREATE OR REPLACE FUNCTION trazabilidad.trz_registrar_cambio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
    v_codigo_evento text := lower(TG_OP);
    v_tabla_id bigint;
    v_tabla_habilitada boolean;
    v_usuario_id bigint;
    v_usuario_aplicacion text;
    v_evento_id bigint;
    v_fila_anterior jsonb;
    v_fila_nueva jsonb;
    v_clave_anterior jsonb;
    v_clave_nueva jsonb;
    v_clave_fila jsonb;
    v_columna record;
    v_valor_anterior jsonb;
    v_valor_nuevo jsonb;
BEGIN
    -- Lee el usuario que la aplicación establece para esta transacción.
    -- Si el cambio no viene de la web, el valor será NULL.
    v_usuario_aplicacion :=
        NULLIF(current_setting('trazabilidad.usuario_aplicacion', true), '');

    SELECT tabla_auditada_id, habilitada
      INTO v_tabla_id, v_tabla_habilitada
      FROM trazabilidad.trz_tabla_origen
     WHERE esquema_origen = TG_TABLE_SCHEMA::name
       AND nombre_tabla = TG_TABLE_NAME::name;

    IF NOT FOUND OR NOT v_tabla_habilitada THEN
        RETURN NULL;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        v_fila_anterior := to_jsonb(OLD);
    END IF;

    IF TG_OP <> 'DELETE' THEN
        v_fila_nueva := to_jsonb(NEW);
    END IF;

    -- Obtiene la clave primaria respetando el orden de sus columnas.
    -- También funciona con claves compuestas.
    IF TG_OP <> 'INSERT' THEN
        SELECT jsonb_object_agg(
                   a.attname,
                   v_fila_anterior -> a.attname
                   ORDER BY key_col.posicion
               )
          INTO v_clave_anterior
          FROM pg_catalog.pg_constraint AS pk
          CROSS JOIN LATERAL unnest(pk.conkey)
              WITH ORDINALITY AS key_col(attnum, posicion)
          JOIN pg_catalog.pg_attribute AS a
            ON a.attrelid = pk.conrelid
           AND a.attnum = key_col.attnum
         WHERE pk.conrelid = TG_RELID
           AND pk.contype = 'p';
    END IF;

    IF TG_OP <> 'DELETE' THEN
        SELECT jsonb_object_agg(
                   a.attname,
                   v_fila_nueva -> a.attname
                   ORDER BY key_col.posicion
               )
          INTO v_clave_nueva
          FROM pg_catalog.pg_constraint AS pk
          CROSS JOIN LATERAL unnest(pk.conkey)
              WITH ORDINALITY AS key_col(attnum, posicion)
          JOIN pg_catalog.pg_attribute AS a
            ON a.attrelid = pk.conrelid
           AND a.attnum = key_col.attnum
         WHERE pk.conrelid = TG_RELID
           AND pk.contype = 'p';
    END IF;

    -- Conserva la clave anterior y nueva. Si la tabla no tiene clave
    -- primaria, clave_fila queda en NULL.
    IF v_clave_anterior IS NOT NULL OR v_clave_nueva IS NOT NULL THEN
        v_clave_fila := jsonb_build_object(
            'anterior', v_clave_anterior,
            'nuevo', v_clave_nueva
        );
    END IF;

    -- Recorre una sola vez las columnas y reglas activas.
    FOR v_columna IN
        SELECT
            ce.configuracion_evento_id,
            ca.nombre_columna
        FROM trazabilidad.trz_columna_origen AS ca
        JOIN trazabilidad.trz_regla_auditoria AS ce
          ON ce.columna_auditada_id = ca.columna_auditada_id
        WHERE ca.tabla_auditada_id = v_tabla_id
          AND ca.habilitada
          AND ce.habilitada
          AND ce.codigo_evento = v_codigo_evento
    LOOP
        v_valor_anterior := NULL;
        v_valor_nuevo := NULL;

        IF TG_OP <> 'INSERT' THEN
            v_valor_anterior :=
                v_fila_anterior -> v_columna.nombre_columna::text;
        END IF;

        IF TG_OP <> 'DELETE' THEN
            v_valor_nuevo :=
                v_fila_nueva -> v_columna.nombre_columna::text;
        END IF;

        -- No registra detalles de columnas sin cambios durante UPDATE.
        IF TG_OP = 'UPDATE'
           AND v_valor_anterior IS NOT DISTINCT FROM v_valor_nuevo THEN
            CONTINUE;
        END IF;

        -- Crea el evento al encontrar el primer detalle válido.
        IF v_evento_id IS NULL THEN
            SELECT usuario_auditado_id
              INTO v_usuario_id
              FROM trazabilidad.trz_usuario
             WHERE nombre_usuario_bd = session_user
               AND habilitado;

            IF NOT FOUND THEN
                v_usuario_id := NULL;
            END IF;

            INSERT INTO trazabilidad.trz_evento (
                tabla_auditada_id,
                codigo_evento,
                usuario_auditado_id,
                usuario_snapshot,
                usuario_aplicacion_snapshot,
                direccion_ip,
                clave_fila,
                fila_anterior,
                fila_nueva
            )
            VALUES (
                v_tabla_id,
                v_codigo_evento,
                v_usuario_id,
                session_user,
                v_usuario_aplicacion,
                inet_client_addr(),
                v_clave_fila,
                v_fila_anterior,
                v_fila_nueva
            )
            RETURNING evento_auditoria_id INTO v_evento_id;
        END IF;

        INSERT INTO trazabilidad.trz_cambio_columna (
            evento_auditoria_id,
            configuracion_evento_id,
            codigo_evento,
            nombre_columna_snapshot,
            valor_anterior,
            valor_nuevo
        )
        VALUES (
            v_evento_id,
            v_columna.configuracion_evento_id,
            v_codigo_evento,
            v_columna.nombre_columna,
            v_valor_anterior,
            v_valor_nuevo
        );
    END LOOP;

    RETURN NULL;
END;
$function$;