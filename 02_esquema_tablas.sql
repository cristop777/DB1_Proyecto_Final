-- Crea las tablas del sistema de trazabilidad.
-- Ejecuta este archivo conectado a control_cambios_db,
-- después de crear el esquema trazabilidad con 01_crear_schema.sql.

-- Tabla de estaciones de trabajo desde las que se originan los cambios.
CREATE TABLE trazabilidad.trz_estacion (
    estacion_trabajo_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    nombre_estacion text NOT NULL,
    direccion_ip inet NULL,
    habilitada boolean DEFAULT true NOT NULL,

    CONSTRAINT trz_estacion_nombre_uq
        UNIQUE (nombre_estacion),

    CONSTRAINT trz_estacion_pk
        PRIMARY KEY (estacion_trabajo_id)
);


-- Catálogo de operaciones que el sistema puede auditar.
CREATE TABLE trazabilidad.trz_tipo_operacion (
    codigo text NOT NULL,
    descripcion text NOT NULL,

    CONSTRAINT trz_tipo_operacion_codigo_ck
        CHECK (codigo IN ('insert', 'update', 'delete')),

    CONSTRAINT trz_tipo_operacion_pk
        PRIMARY KEY (codigo)
);


-- Usuarios de PostgreSQL que pueden aparecer en los eventos auditados.
CREATE TABLE trazabilidad.trz_usuario (
    usuario_auditado_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    nombre_usuario_bd name COLLATE "C" NOT NULL,
    nombre_visible text NULL,
    habilitado boolean DEFAULT true NOT NULL,

    CONSTRAINT trz_usuario_nombre_bd_uq
        UNIQUE (nombre_usuario_bd),

    CONSTRAINT trz_usuario_pk
        PRIMARY KEY (usuario_auditado_id)
);


-- Tablas de la base de datos configuradas para auditoría.
CREATE TABLE trazabilidad.trz_tabla_origen (
    tabla_auditada_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    esquema_origen name COLLATE "C" NOT NULL,
    nombre_tabla name COLLATE "C" NOT NULL,
    habilitada boolean DEFAULT false NOT NULL,
    fecha_creacion timestamp with time zone
        DEFAULT CURRENT_TIMESTAMP NOT NULL,

    CONSTRAINT trz_tabla_origen_esquema_nombre_uq
        UNIQUE (esquema_origen, nombre_tabla),

    CONSTRAINT trz_tabla_origen_pk
        PRIMARY KEY (tabla_auditada_id)
);


-- Columnas seleccionadas para auditoría dentro de cada tabla de origen.
CREATE TABLE trazabilidad.trz_columna_origen (
    columna_auditada_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    tabla_auditada_id bigint NOT NULL,
    nombre_columna name COLLATE "C" NOT NULL,
    tipo_dato text NULL,
    posicion integer NULL,
    habilitada boolean DEFAULT false NOT NULL,

    CONSTRAINT trz_columna_origen_posicion_ck
        CHECK (posicion IS NULL OR posicion > 0),

    CONSTRAINT trz_columna_origen_tabla_nombre_uq
        UNIQUE (tabla_auditada_id, nombre_columna),

    CONSTRAINT trz_columna_origen_pk
        PRIMARY KEY (columna_auditada_id),

    CONSTRAINT trz_columna_origen_tabla_fk
        FOREIGN KEY (tabla_auditada_id)
        REFERENCES trazabilidad.trz_tabla_origen (tabla_auditada_id)
        ON DELETE RESTRICT
);


-- Reglas que indican qué operaciones se registrarán por columna.
CREATE TABLE trazabilidad.trz_regla_auditoria (
    configuracion_evento_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    columna_auditada_id bigint NOT NULL,
    codigo_evento text NOT NULL,
    habilitada boolean DEFAULT false NOT NULL,

    CONSTRAINT trz_regla_columna_operacion_uq
        UNIQUE (columna_auditada_id, codigo_evento),

    -- Esta restricción compuesta permite validar la operación
    -- al insertar el detalle de un evento.
    CONSTRAINT trz_regla_id_operacion_uq
        UNIQUE (configuracion_evento_id, codigo_evento),

    CONSTRAINT trz_regla_auditoria_pk
        PRIMARY KEY (configuracion_evento_id),

    CONSTRAINT trz_regla_tipo_operacion_fk
        FOREIGN KEY (codigo_evento)
        REFERENCES trazabilidad.trz_tipo_operacion (codigo)
        ON DELETE RESTRICT,

    CONSTRAINT trz_regla_columna_fk
        FOREIGN KEY (columna_auditada_id)
        REFERENCES trazabilidad.trz_columna_origen (columna_auditada_id)
        ON DELETE RESTRICT
);


-- Registro general de cada operación realizada en una tabla auditada.
-- Conserva snapshots de la fila y su clave, incluso si luego se elimina
-- el registro original.
CREATE TABLE trazabilidad.trz_evento (
    evento_auditoria_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    tabla_auditada_id bigint NOT NULL,
    codigo_evento text NOT NULL,
    usuario_auditado_id bigint NULL,
    estacion_trabajo_id bigint NULL,
    usuario_snapshot name COLLATE "C"
        DEFAULT SESSION_USER NOT NULL,
    estacion_snapshot text NULL,
    direccion_ip inet NULL,
    fecha_evento timestamp with time zone
        DEFAULT clock_timestamp() NOT NULL,
    fila_anterior jsonb NULL,
    fila_nueva jsonb NULL,
    clave_fila jsonb NULL,

    CONSTRAINT trz_evento_operacion_fila_ck
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

    -- Clave compuesta usada para validar la operación
    -- desde el detalle del evento.
    CONSTRAINT trz_evento_id_operacion_uq
        UNIQUE (evento_auditoria_id, codigo_evento),

    CONSTRAINT trz_evento_pk
        PRIMARY KEY (evento_auditoria_id),

    CONSTRAINT trz_evento_tipo_operacion_fk
        FOREIGN KEY (codigo_evento)
        REFERENCES trazabilidad.trz_tipo_operacion (codigo)
        ON DELETE RESTRICT,

    CONSTRAINT trz_evento_estacion_fk
        FOREIGN KEY (estacion_trabajo_id)
        REFERENCES trazabilidad.trz_estacion (estacion_trabajo_id)
        ON DELETE SET NULL,

    CONSTRAINT trz_evento_tabla_origen_fk
        FOREIGN KEY (tabla_auditada_id)
        REFERENCES trazabilidad.trz_tabla_origen (tabla_auditada_id)
        ON DELETE RESTRICT,

    CONSTRAINT trz_evento_usuario_fk
        FOREIGN KEY (usuario_auditado_id)
        REFERENCES trazabilidad.trz_usuario (usuario_auditado_id)
        ON DELETE SET NULL
);


-- Índices para acelerar búsquedas cronológicas y por tabla o usuario.
CREATE INDEX trz_evento_fecha_idx
    ON trazabilidad.trz_evento (fecha_evento DESC);

CREATE INDEX trz_evento_tabla_fecha_idx
    ON trazabilidad.trz_evento
       (tabla_auditada_id, fecha_evento DESC);

CREATE INDEX trz_evento_usuario_fecha_idx
    ON trazabilidad.trz_evento
       (usuario_snapshot, fecha_evento DESC);


-- Detalle por columna afectada en cada evento.
-- Guarda los valores anteriores y nuevos según la regla aplicada.
CREATE TABLE trazabilidad.trz_cambio_columna (
    detalle_auditoria_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    evento_auditoria_id bigint NOT NULL,
    configuracion_evento_id bigint NOT NULL,
    codigo_evento text NOT NULL,
    nombre_columna_snapshot name COLLATE "C" NOT NULL,
    valor_anterior jsonb NULL,
    valor_nuevo jsonb NULL,

    CONSTRAINT trz_cambio_evento_regla_uq
        UNIQUE (evento_auditoria_id, configuracion_evento_id),

    CONSTRAINT trz_cambio_columna_pk
        PRIMARY KEY (detalle_auditoria_id),

    CONSTRAINT trz_cambio_regla_operacion_fk
        FOREIGN KEY (configuracion_evento_id, codigo_evento)
        REFERENCES trazabilidad.trz_regla_auditoria
            (configuracion_evento_id, codigo_evento)
        ON DELETE RESTRICT,

    CONSTRAINT trz_cambio_evento_operacion_fk
        FOREIGN KEY (evento_auditoria_id, codigo_evento)
        REFERENCES trazabilidad.trz_evento
            (evento_auditoria_id, codigo_evento)
        ON DELETE RESTRICT
);


-- Índice para consultas por regla de configuración.
CREATE INDEX trz_cambio_regla_idx
    ON trazabilidad.trz_cambio_columna (configuracion_evento_id);


-- Índice para buscar cambios por columna y evento.
CREATE INDEX trz_cambio_columna_evento_idx
    ON trazabilidad.trz_cambio_columna
       (nombre_columna_snapshot, evento_auditoria_id);


-- Registra las operaciones admitidas por el sistema.
INSERT INTO trazabilidad.trz_tipo_operacion (codigo, descripcion)
VALUES
    ('insert', 'Inserción'),
    ('update', 'Actualización'),
    ('delete', 'Eliminación')
ON CONFLICT (codigo)
DO UPDATE SET descripcion = EXCLUDED.descripcion;