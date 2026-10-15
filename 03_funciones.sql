-- crea las funciones para auditoria

CREATE OR REPLACE FUNCTION autoaudit.configurar_columna(p_esquema name, p_tabla name, p_columna name, p_operaciones text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
    v_tabla_id bigint;
    v_columna_id bigint;
BEGIN
    IF p_operaciones IS NULL OR cardinality(p_operaciones) = 0 THEN
        RAISE EXCEPTION 'Indica al menos una operación para auditar';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(p_operaciones) AS op(codigo)
        WHERE op.codigo IS NULL
           OR lower(op.codigo) NOT IN ('insert', 'update', 'delete')
    ) THEN
        RAISE EXCEPTION 'Operaciones válidas: insert, update y delete';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables AS t
        WHERE t.table_schema = p_esquema::text
          AND t.table_name = p_tabla::text
          AND t.table_type = 'BASE TABLE'
          AND t.table_schema <> 'information_schema'
          AND left(t.table_schema, 3) <> 'pg_'
          AND t.table_schema <> 'autoaudit'
    ) THEN
        RAISE EXCEPTION 'No existe la tabla de usuario %.%', p_esquema, p_tabla;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns AS c
        WHERE c.table_schema = p_esquema::text
          AND c.table_name = p_tabla::text
          AND c.column_name = p_columna::text
    ) THEN
        RAISE EXCEPTION 'No existe la columna % en %.%',
            p_columna, p_esquema, p_tabla;
    END IF;

    INSERT INTO autoaudit.tabla_auditada (esquema_origen, nombre_tabla)
    VALUES (p_esquema, p_tabla)
    ON CONFLICT (esquema_origen, nombre_tabla) DO NOTHING;

    SELECT tabla_auditada_id
      INTO v_tabla_id
      FROM autoaudit.tabla_auditada
     WHERE esquema_origen = p_esquema
       AND nombre_tabla = p_tabla;

    UPDATE autoaudit.tabla_auditada
       SET habilitada = true
     WHERE tabla_auditada_id = v_tabla_id;

    INSERT INTO autoaudit.columna_auditada (
        tabla_auditada_id,
        nombre_columna,
        tipo_dato,
        posicion,
        habilitada
    )
    SELECT
        v_tabla_id,
        c.column_name::name,
        c.data_type,
        c.ordinal_position,
        true
    FROM information_schema.columns AS c
    WHERE c.table_schema = p_esquema::text
      AND c.table_name = p_tabla::text
      AND c.column_name = p_columna::text
    ON CONFLICT (tabla_auditada_id, nombre_columna)
    DO UPDATE SET
        tipo_dato = EXCLUDED.tipo_dato,
        posicion = EXCLUDED.posicion,
        habilitada = true
    RETURNING columna_auditada_id INTO v_columna_id;

    INSERT INTO autoaudit.configuracion_evento (
        columna_auditada_id,
        codigo_evento,
        habilitada
    )
    SELECT DISTINCT
        v_columna_id,
        lower(op.codigo),
        true
    FROM unnest(p_operaciones) AS op(codigo)
    ON CONFLICT (columna_auditada_id, codigo_evento)
    DO UPDATE SET habilitada = true;

    PERFORM autoaudit.instalar_trigger(v_tabla_id);
END;
$function$
;

-- DROP FUNCTION autoaudit.desactivar_operacion(name, name, name, text);

CREATE OR REPLACE FUNCTION autoaudit.desactivar_operacion(p_esquema name, p_tabla name, p_columna name, p_operacion text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
    v_tabla_id bigint;
    v_columna_id bigint;
    v_operacion text := lower(p_operacion);
    v_trigger name;
BEGIN
    IF v_operacion NOT IN ('insert', 'update', 'delete') THEN
        RAISE EXCEPTION 'Operación inválida: %', p_operacion;
    END IF;

    SELECT ta.tabla_auditada_id, ca.columna_auditada_id
      INTO v_tabla_id, v_columna_id
      FROM autoaudit.tabla_auditada AS ta
      JOIN autoaudit.columna_auditada AS ca
        ON ca.tabla_auditada_id = ta.tabla_auditada_id
     WHERE ta.esquema_origen = p_esquema
       AND ta.nombre_tabla = p_tabla
       AND ca.nombre_columna = p_columna;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró la columna %.%.%',
            p_esquema, p_tabla, p_columna;
    END IF;

    UPDATE autoaudit.configuracion_evento
       SET habilitada = false
     WHERE columna_auditada_id = v_columna_id
       AND codigo_evento = v_operacion;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La operación % no está configurada para esa columna',
            v_operacion;
    END IF;

    -- Si esa columna ya no tiene operaciones activas, también se deshabilita.
    UPDATE autoaudit.columna_auditada AS ca
       SET habilitada = false
     WHERE ca.columna_auditada_id = v_columna_id
       AND NOT EXISTS (
           SELECT 1
           FROM autoaudit.configuracion_evento AS ce
           WHERE ce.columna_auditada_id = ca.columna_auditada_id
             AND ce.habilitada
       );

    -- Si ninguna columna de la tabla sigue habilitada, se apaga la tabla
    -- y se elimina el trigger generado.
    IF NOT EXISTS (
        SELECT 1
        FROM autoaudit.columna_auditada AS ca
        JOIN autoaudit.configuracion_evento AS ce
          ON ce.columna_auditada_id = ca.columna_auditada_id
        WHERE ca.tabla_auditada_id = v_tabla_id
          AND ca.habilitada
          AND ce.habilitada
    ) THEN
        UPDATE autoaudit.tabla_auditada
           SET habilitada = false
         WHERE tabla_auditada_id = v_tabla_id;

        SELECT ('trg_autoaudit_' || v_tabla_id::text)::name
          INTO v_trigger;

        IF to_regclass(format('%I.%I', p_esquema, p_tabla)) IS NOT NULL THEN
            EXECUTE format(
                'DROP TRIGGER IF EXISTS %I ON %I.%I',
                v_trigger, p_esquema, p_tabla
            );
        END IF;
    END IF;
END;
$function$
;

-- DROP FUNCTION autoaudit.desactivar_tabla(name, name);

CREATE OR REPLACE FUNCTION autoaudit.desactivar_tabla(p_esquema name, p_tabla name)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
    v_tabla_id bigint;
    v_trigger name;
BEGIN
    SELECT tabla_auditada_id
      INTO v_tabla_id
      FROM autoaudit.tabla_auditada
     WHERE esquema_origen = p_esquema
       AND nombre_tabla = p_tabla;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró la tabla configurada %.%',
            p_esquema, p_tabla;
    END IF;

    UPDATE autoaudit.configuracion_evento AS ce
       SET habilitada = false
      FROM autoaudit.columna_auditada AS ca
     WHERE ca.tabla_auditada_id = v_tabla_id
       AND ce.columna_auditada_id = ca.columna_auditada_id;

    UPDATE autoaudit.columna_auditada
       SET habilitada = false
     WHERE tabla_auditada_id = v_tabla_id;

    UPDATE autoaudit.tabla_auditada
       SET habilitada = false
     WHERE tabla_auditada_id = v_tabla_id;

    SELECT ('trg_autoaudit_' || v_tabla_id::text)::name
      INTO v_trigger;

    IF to_regclass(format('%I.%I', p_esquema, p_tabla)) IS NOT NULL THEN
        EXECUTE format(
            'DROP TRIGGER IF EXISTS %I ON %I.%I',
            v_trigger, p_esquema, p_tabla
        );
    END IF;
END;
$function$
;

-- DROP FUNCTION autoaudit.fn_completar_contexto();

CREATE OR REPLACE FUNCTION autoaudit.fn_completar_contexto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
    v_estacion_solicitada text;
    v_estacion_id bigint;
    v_estacion_nombre text;
BEGIN
    NEW.direccion_ip := COALESCE(NEW.direccion_ip, inet_client_addr());

    v_estacion_solicitada :=
        NULLIF(current_setting('autoaudit.estacion_nombre', true), '');

    IF v_estacion_solicitada IS NOT NULL THEN
        SELECT estacion_trabajo_id, nombre_estacion
          INTO v_estacion_id, v_estacion_nombre
          FROM autoaudit.estacion_trabajo
         WHERE nombre_estacion = v_estacion_solicitada
           AND habilitada;

        IF FOUND THEN
            NEW.estacion_trabajo_id := v_estacion_id;
            NEW.estacion_snapshot := v_estacion_nombre;
        ELSE
            -- Conserva el nombre informado aunque no esté registrado.
            NEW.estacion_trabajo_id := NULL;
            NEW.estacion_snapshot := v_estacion_solicitada;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$
;

-- DROP FUNCTION autoaudit.fn_registrar_cambio();

-- Registra los cambios de una fila y los detalles de las columnas configuradas.
-- Recorre la configuración una sola vez y crea el evento solo al encontrar
-- el primer detalle válido. En UPDATE, ignora columnas cuyo valor no cambió.
CREATE OR REPLACE FUNCTION autoaudit.fn_registrar_cambio()
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
    v_evento_id bigint;
    v_fila_anterior jsonb;
    v_fila_nueva jsonb;
    v_columna record;
    v_valor_anterior jsonb;
    v_valor_nuevo jsonb;
BEGIN
    SELECT tabla_auditada_id, habilitada
      INTO v_tabla_id, v_tabla_habilitada
      FROM autoaudit.tabla_auditada
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

    -- Recorre una sola vez las columnas habilitadas para esta operación.
    FOR v_columna IN
        SELECT
            ce.configuracion_evento_id,
            ca.nombre_columna
        FROM autoaudit.columna_auditada AS ca
        JOIN autoaudit.configuracion_evento AS ce
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

        -- Evita registrar detalles de columnas sin cambios en UPDATE.
        IF TG_OP = 'UPDATE'
           AND v_valor_anterior IS NOT DISTINCT FROM v_valor_nuevo THEN
            CONTINUE;
        END IF;

        -- Crea el evento al encontrar el primer detalle válido. De esta forma,
        -- no se guarda un evento vacío si no hay columnas configuradas o cambiadas.
        IF v_evento_id IS NULL THEN
            SELECT usuario_auditado_id
              INTO v_usuario_id
              FROM autoaudit.usuario_auditado
             WHERE nombre_usuario_bd = session_user
               AND habilitado;

            IF NOT FOUND THEN
                v_usuario_id := NULL;
            END IF;

            INSERT INTO autoaudit.evento_auditoria (
                tabla_auditada_id,
                codigo_evento,
                usuario_auditado_id,
                usuario_snapshot,
                direccion_ip,
                fila_anterior,
                fila_nueva
            )
            VALUES (
                v_tabla_id,
                v_codigo_evento,
                v_usuario_id,
                session_user,
                inet_client_addr(),
                v_fila_anterior,
                v_fila_nueva
            )
            RETURNING evento_auditoria_id INTO v_evento_id;
        END IF;

        INSERT INTO autoaudit.detalle_auditoria (
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
$function$
;
-- DROP FUNCTION autoaudit.instalar_trigger(int8);

CREATE OR REPLACE FUNCTION autoaudit.instalar_trigger(p_tabla_auditada_id bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_esquema name;
    v_tabla name;
    v_habilitada boolean;
    v_trigger name;
BEGIN
    SELECT esquema_origen, nombre_tabla, habilitada
      INTO v_esquema, v_tabla, v_habilitada
      FROM autoaudit.tabla_auditada
     WHERE tabla_auditada_id = p_tabla_auditada_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la configuración de tabla %',
            p_tabla_auditada_id;
    END IF;

    IF NOT v_habilitada THEN
        RAISE EXCEPTION 'La tabla configurada está deshabilitada';
    END IF;

    IF to_regclass(format('%I.%I', v_esquema, v_tabla)) IS NULL THEN
        RAISE EXCEPTION 'No existe la tabla %.%', v_esquema, v_tabla;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM autoaudit.columna_auditada AS ca
        JOIN autoaudit.configuracion_evento AS ce
          ON ce.columna_auditada_id = ca.columna_auditada_id
        WHERE ca.tabla_auditada_id = p_tabla_auditada_id
          AND ca.habilitada
          AND ce.habilitada
    ) THEN
        RAISE EXCEPTION 'La tabla no tiene columnas y operaciones habilitadas';
    END IF;

    v_trigger := ('trg_autoaudit_' || p_tabla_auditada_id::text)::name;

    EXECUTE format(
        'DROP TRIGGER IF EXISTS %I ON %I.%I',
        v_trigger, v_esquema, v_tabla
    );

    EXECUTE format(
        'CREATE TRIGGER %I
         AFTER INSERT OR UPDATE OR DELETE ON %I.%I
         FOR EACH ROW
         EXECUTE FUNCTION autoaudit.fn_registrar_cambio()',
        v_trigger, v_esquema, v_tabla
    );
END;
$function$
;

-- DROP FUNCTION autoaudit.sincronizar_diccionario();

CREATE OR REPLACE FUNCTION autoaudit.sincronizar_diccionario()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
    INSERT INTO autoaudit.tabla_auditada (
        esquema_origen,
        nombre_tabla
    )
    SELECT
        t.table_schema::name,
        t.table_name::name
    FROM information_schema.tables AS t
    WHERE t.table_type = 'BASE TABLE'
      AND t.table_schema <> 'information_schema'
      AND left(t.table_schema, 3) <> 'pg_'
      AND t.table_schema <> 'autoaudit'
    ON CONFLICT (esquema_origen, nombre_tabla) DO NOTHING;

    INSERT INTO autoaudit.columna_auditada (
        tabla_auditada_id,
        nombre_columna,
        tipo_dato,
        posicion
    )
    SELECT
        ta.tabla_auditada_id,
        c.column_name::name,
        c.data_type,
        c.ordinal_position
    FROM information_schema.columns AS c
    JOIN autoaudit.tabla_auditada AS ta
      ON ta.esquema_origen = c.table_schema::name
     AND ta.nombre_tabla = c.table_name::name
    WHERE c.table_schema <> 'information_schema'
      AND left(c.table_schema, 3) <> 'pg_'
      AND c.table_schema <> 'autoaudit'
    ON CONFLICT (tabla_auditada_id, nombre_columna)
    DO UPDATE SET
        tipo_dato = EXCLUDED.tipo_dato,
        posicion = EXCLUDED.posicion;
END;
$function$
;
