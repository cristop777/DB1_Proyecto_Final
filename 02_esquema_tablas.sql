-- Crea las tablas necesarias para auditoria

-- autoaudit.estacion_trabajo definition

-- Drop table

-- DROP TABLE autoaudit.estacion_trabajo;

CREATE TABLE autoaudit.estacion_trabajo (
    estacion_trabajo_id int8 GENERATED ALWAYS AS IDENTITY
        (INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807
         START 1 CACHE 1 NO CYCLE) NOT NULL,
    nombre_estacion text NOT NULL,
    direccion_ip inet NULL,
    habilitada bool DEFAULT true NOT NULL,
    CONSTRAINT estacion_trabajo_nombre_estacion_key
        UNIQUE (nombre_estacion),
    CONSTRAINT estacion_trabajo_pkey
        PRIMARY KEY (estacion_trabajo_id)
);


-- autoaudit.tabla_auditada definition

-- Drop table

-- DROP TABLE autoaudit.tabla_auditada;

CREATE TABLE autoaudit.tabla_auditada (
    tabla_auditada_id int8 GENERATED ALWAYS AS IDENTITY
        (INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807
         START 1 CACHE 1 NO CYCLE) NOT NULL,
    esquema_origen name COLLATE "C" NOT NULL,
    nombre_tabla name COLLATE "C" NOT NULL,
    habilitada bool DEFAULT false NOT NULL,
    fecha_creacion timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT tabla_auditada_esquema_origen_nombre_tabla_key
        UNIQUE (esquema_origen, nombre_tabla),
    CONSTRAINT tabla_auditada_pkey
        PRIMARY KEY (tabla_auditada_id)
);


-- autoaudit.tipo_evento definition

-- Drop table

-- DROP TABLE autoaudit.tipo_evento;

CREATE TABLE autoaudit.tipo_evento (
    codigo text NOT NULL,
    descripcion text NOT NULL,
    CONSTRAINT tipo_evento_codigo_check
        CHECK (codigo IN ('insert', 'update', 'delete')),
    CONSTRAINT tipo_evento_pkey
        PRIMARY KEY (codigo)
);


-- autoaudit.usuario_auditado definition

-- Drop table

-- DROP TABLE autoaudit.usuario_auditado;

CREATE TABLE autoaudit.usuario_auditado (
    usuario_auditado_id int8 GENERATED ALWAYS AS IDENTITY
        (INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807
         START 1 CACHE 1 NO CYCLE) NOT NULL,
    nombre_usuario_bd name COLLATE "C" NOT NULL,
    nombre_visible text NULL,
    habilitado bool DEFAULT true NOT NULL,
    CONSTRAINT usuario_auditado_nombre_usuario_bd_key
        UNIQUE (nombre_usuario_bd),
    CONSTRAINT usuario_auditado_pkey
        PRIMARY KEY (usuario_auditado_id)
);


-- autoaudit.columna_auditada definition

-- Drop table

-- DROP TABLE autoaudit.columna_auditada;

CREATE TABLE autoaudit.columna_auditada (
    columna_auditada_id int8 GENERATED ALWAYS AS IDENTITY
        (INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807
         START 1 CACHE 1 NO CYCLE) NOT NULL,
    tabla_auditada_id int8 NOT NULL,
    nombre_columna name COLLATE "C" NOT NULL,
    tipo_dato text NULL,
    posicion int4 NULL,
    habilitada bool DEFAULT false NOT NULL,
    CONSTRAINT columna_auditada_posicion_check
        CHECK (posicion IS NULL OR posicion > 0),
    CONSTRAINT columna_auditada_tabla_auditada_id_nombre_columna_key
        UNIQUE (tabla_auditada_id, nombre_columna),
    CONSTRAINT columna_auditada_pkey
        PRIMARY KEY (columna_auditada_id),
    CONSTRAINT columna_auditada_tabla_auditada_id_fkey
        FOREIGN KEY (tabla_auditada_id)
        REFERENCES autoaudit.tabla_auditada (tabla_auditada_id)
        ON DELETE RESTRICT
);


-- autoaudit.configuracion_evento definition

-- Drop table

-- DROP TABLE autoaudit.configuracion_evento;

CREATE TABLE autoaudit.configuracion_evento (
    configuracion_evento_id int8 GENERATED ALWAYS AS IDENTITY
        (INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807
         START 1 CACHE 1 NO CYCLE) NOT NULL,
    columna_auditada_id int8 NOT NULL,
    codigo_evento text NOT NULL,
    habilitada bool DEFAULT false NOT NULL,
    CONSTRAINT configuracion_evento_columna_auditada_id_codigo_evento_key
        UNIQUE (columna_auditada_id, codigo_evento),
    CONSTRAINT configuracion_evento_configuracion_evento_id_codigo_evento_key
        UNIQUE (configuracion_evento_id, codigo_evento),
    CONSTRAINT configuracion_evento_pkey
        PRIMARY KEY (configuracion_evento_id),
    CONSTRAINT configuracion_evento_codigo_evento_fkey
        FOREIGN KEY (codigo_evento)
        REFERENCES autoaudit.tipo_evento (codigo)
        ON DELETE RESTRICT,
    CONSTRAINT configuracion_evento_columna_auditada_id_fkey
        FOREIGN KEY (columna_auditada_id)
        REFERENCES autoaudit.columna_auditada (columna_auditada_id)
        ON DELETE RESTRICT
);


-- autoaudit.evento_auditoria definition

-- Drop table

-- DROP TABLE autoaudit.evento_auditoria;

CREATE TABLE autoaudit.evento_auditoria (
    evento_auditoria_id int8 GENERATED ALWAYS AS IDENTITY
        (INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807
         START 1 CACHE 1 NO CYCLE) NOT NULL,
    tabla_auditada_id int8 NOT NULL,
    codigo_evento text NOT NULL,
    usuario_auditado_id int8 NULL,
    estacion_trabajo_id int8 NULL,
    usuario_snapshot name COLLATE "C" DEFAULT SESSION_USER NOT NULL,
    estacion_snapshot text NULL,
    direccion_ip inet NULL,
    fecha_evento timestamptz DEFAULT clock_timestamp() NOT NULL,
    fila_anterior jsonb NULL,
    fila_nueva jsonb NULL,
    clave_fila jsonb NULL,
    CONSTRAINT evento_auditoria_check
        CHECK (
            (codigo_evento = 'insert'
                AND fila_anterior IS NULL
                AND fila_nueva IS NOT NULL)
            OR
            (codigo_evento = 'update'
                AND fila_anterior IS NOT NULL
                AND fila_nueva IS NOT NULL)
            OR
            (codigo_evento = 'delete'
                AND fila_anterior IS NOT NULL
                AND fila_nueva IS NULL)
        ),
    CONSTRAINT evento_auditoria_evento_auditoria_id_codigo_evento_key
        UNIQUE (evento_auditoria_id, codigo_evento),
    CONSTRAINT evento_auditoria_pkey
        PRIMARY KEY (evento_auditoria_id),
    CONSTRAINT evento_auditoria_codigo_evento_fkey
        FOREIGN KEY (codigo_evento)
        REFERENCES autoaudit.tipo_evento (codigo)
        ON DELETE RESTRICT,
    CONSTRAINT evento_auditoria_estacion_trabajo_id_fkey
        FOREIGN KEY (estacion_trabajo_id)
        REFERENCES autoaudit.estacion_trabajo (estacion_trabajo_id)
        ON DELETE SET NULL,
    CONSTRAINT evento_auditoria_tabla_auditada_id_fkey
        FOREIGN KEY (tabla_auditada_id)
        REFERENCES autoaudit.tabla_auditada (tabla_auditada_id)
        ON DELETE RESTRICT,
    CONSTRAINT evento_auditoria_usuario_auditado_id_fkey
        FOREIGN KEY (usuario_auditado_id)
        REFERENCES autoaudit.usuario_auditado (usuario_auditado_id)
        ON DELETE SET NULL
);

-- Índices para búsquedas por fecha, tabla auditada y usuario.
CREATE INDEX evento_auditoria_fecha_idx
    ON autoaudit.evento_auditoria (fecha_evento DESC);

CREATE INDEX evento_auditoria_tabla_fecha_idx
    ON autoaudit.evento_auditoria (tabla_auditada_id, fecha_evento DESC);

CREATE INDEX evento_auditoria_usuario_fecha_idx
    ON autoaudit.evento_auditoria (usuario_snapshot, fecha_evento DESC);


-- autoaudit.detalle_auditoria definition

-- Drop table

-- DROP TABLE autoaudit.detalle_auditoria;

CREATE TABLE autoaudit.detalle_auditoria (
    detalle_auditoria_id int8 GENERATED ALWAYS AS IDENTITY
        (INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807
         START 1 CACHE 1 NO CYCLE) NOT NULL,
    evento_auditoria_id int8 NOT NULL,
    configuracion_evento_id int8 NOT NULL,
    codigo_evento text NOT NULL,
    nombre_columna_snapshot name COLLATE "C" NOT NULL,
    valor_anterior jsonb NULL,
    valor_nuevo jsonb NULL,
    CONSTRAINT detalle_auditoria_evento_auditoria_id_configuracion_evento_key
        UNIQUE (evento_auditoria_id, configuracion_evento_id),
    CONSTRAINT detalle_auditoria_pkey
        PRIMARY KEY (detalle_auditoria_id),
    CONSTRAINT detalle_auditoria_configuracion_evento_id_codigo_evento_fkey
        FOREIGN KEY (configuracion_evento_id, codigo_evento)
        REFERENCES autoaudit.configuracion_evento
            (configuracion_evento_id, codigo_evento)
        ON DELETE RESTRICT,
    CONSTRAINT detalle_auditoria_evento_auditoria_id_codigo_evento_fkey
        FOREIGN KEY (evento_auditoria_id, codigo_evento)
        REFERENCES autoaudit.evento_auditoria
            (evento_auditoria_id, codigo_evento)
        ON DELETE RESTRICT
);

-- Índice para relacionar el detalle con la configuración del evento.
CREATE INDEX detalle_auditoria_configuracion_idx
    ON autoaudit.detalle_auditoria (configuracion_evento_id);

-- Índice para buscar rápidamente los cambios de una columna auditada.
CREATE INDEX IF NOT EXISTS detalle_auditoria_columna_evento_idx
    ON autoaudit.detalle_auditoria (
        nombre_columna_snapshot,
        evento_auditoria_id
    );


-- Inserta los tipos de evento admitidos por el sistema.
INSERT INTO autoaudit.tipo_evento (codigo, descripcion)
VALUES
    ('insert', 'Inserción'),
    ('update', 'Actualización'),
    ('delete', 'Eliminación')
ON CONFLICT (codigo)
DO UPDATE SET descripcion = EXCLUDED.descripcion;