# AutoAudit — sistema de auditoría automatizada

Proyecto universitario de base de datos para configurar auditoría por tabla, columna y operación en PostgreSQL. Los cambios se capturan con triggers y se consultan desde una vista histórica.

## Contenido

- 00_crear_base.sql a 08_pruebas_rendimiento.sql: scripts ordenados para creación, configuración, consulta y pruebas.

## Requisitos

- PostgreSQL 18 es la versión objetivo del proyecto.
- DBeaver 26.2.1 se utilizó en las pruebas.
- Ubuntu 26.04 LTS es el sistema operativo objetivo.
- Se requieren privilegios para crear la base, esquema, rol, tablas, funciones y triggers.

PostgreSQL utiliza PL/pgSQL para funciones almacenadas; PL/SQL corresponde principalmente a Oracle.

## Orden de instalación

1. Desde la conexión de mantenimiento postgres, ejecutar 00_crear_base.sql. La creación de la base debe hacerse fuera de una transacción. Si autoaudit_db ya existe, omitir este paso.
2. Conectarse a autoaudit_db y ejecutar en orden 01_crear_schema.sql, 02_esquema_tablas.sql, 03_funciones.sql y 04_permisos.sql.
3. Si otro usuario debe configurar auditoría, otorgarle la membresía del rol autoaudit_admin desde una cuenta autorizada. Sustituye cristop por el usuario correspondiente.
4. Ejecutar 05_configuracion_demo.sql para crear la tabla de demostración, sincronizar el diccionario y activar auditoría en correo.
5. Ejecutar 06_consultas_historial.sql para crear la vista de historial.
6. Ejecutar 07_pruebas_funcionales.sql. Prueba INSERT, UPDATE y DELETE, consulta los resultados y termina con ROLLBACK.
7. Ejecutar por separado cada bloque de 08_pruebas_rendimiento.sql y conservar la salida de EXPLAIN (ANALYZE, BUFFERS).

## Advertencias

- 01_crear_schema.sql elimina y recrea el esquema autoaudit con CASCADE.
- 05_configuracion_demo.sql elimina y recrea public.clientes_demo.
- Ejecutar esos scripts solo en una base de demostración o limpia.
- 08_pruebas_rendimiento.sql espera que el trigger se llame trg_autoaudit_1. Si el ID de tabla genera otro nombre, cambiarlo en el script.

## Estado actual

La versión implementa el módulo de base de datos. La interfaz no está implementada ni tiene tecnología definida. La estación de trabajo se registra si la aplicación la informa dentro de la transacción. La columna clave_fila existe en la bitácora, pero la función actual aún no la completa.

## Repositorio

https://github.com/cristop777/DB1_Proyecto_Final
