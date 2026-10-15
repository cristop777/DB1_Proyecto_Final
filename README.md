# AutoAudit — sistema de auditoría automatizada

Proyecto universitario de base de datos para configurar auditoría por tabla, columna y operación en PostgreSQL. Los cambios se capturan con triggers y se consultan desde una vista histórica.

## Contenido

- `00_crear_base.sql` a `08_pruebas_rendimiento.sql`: scripts ordenados para creación, configuración, consulta y pruebas.
- `manual_tecnico_autoaudit.docx`: manual de instalación, configuración, modelo de datos, consultas y resultados de validación.

## Requisitos

- PostgreSQL 18 (versión objetivo del proyecto).
- DBeaver 26.2.1 se utilizó para las pruebas y ejemplos del manual.
- Una cuenta con privilegios suficientes para crear la base, el esquema, roles, tablas, funciones y triggers.
- Ubuntu 26.04 LTS es el sistema operativo objetivo documentado.

PostgreSQL utiliza PL/pgSQL para las funciones almacenadas. PL/SQL es el lenguaje de Oracle.

## Orden de instalación

1. Desde una conexión a la base de mantenimiento `postgres`, ejecutar `00_crear_base.sql`. La creación de base debe ejecutarse fuera de una transacción. Si `autoaudit_db` ya existe, omitir este paso.
2. Conectarse a `autoaudit_db` y ejecutar, en orden, `01_crear_schema.sql`, `02_esquema_tablas.sql`, `03_funciones.sql` y `04_permisos.sql`.
3. Si un usuario debe configurar auditoría, otorgarle la membresía del rol administrativo desde una cuenta autorizada. Por ejemplo, sustituir `cristop` por el usuario correcto:

   ```sql
   GRANT autoaudit_admin TO cristop;
   ```

4. Ejecutar `05_configuracion_demo.sql` para crear `public.clientes_demo`, sincronizar el diccionario y activar la auditoría de `correo`.
5. Ejecutar `06_consultas_historial.sql` para crear la vista y consultar el historial.
6. Ejecutar `07_pruebas_funcionales.sql` para validar INSERT, UPDATE y DELETE. El script termina con `ROLLBACK`, así que los cambios de esa prueba no quedan guardados.
7. Ejecutar cada bloque de `08_pruebas_rendimiento.sql` por separado y conservar la salida de `EXPLAIN (ANALYZE, BUFFERS)`. El script usa `ROLLBACK` para revertir las filas generadas.

## Advertencias de datos

- `01_crear_schema.sql` ejecuta `DROP SCHEMA IF EXISTS autoaudit CASCADE`: elimina el esquema y los objetos/datos que contiene.
- `05_configuracion_demo.sql` elimina y recrea `public.clientes_demo` con `CASCADE`.
- Ejecutar esos scripts solo en una base limpia o de demostración. No usarlos sobre datos que se deban conservar.
- `08_pruebas_rendimiento.sql` espera que el trigger de demostración se llame `trg_autoaudit_1`. Si el identificador de tabla produjo otro nombre, consultar `pg_trigger` y cambiar el nombre en ese script antes de ejecutarlo.

## Estado y alcance

La versión actual implementa el módulo de base de datos. La interfaz gráfica no está implementada ni tiene tecnología definida. La estación de trabajo se registra si la aplicación la informa dentro de la transacción. La columna `clave_fila` existe en la bitácora, pero la función actual aún no la completa.

El manual reporta los resultados de rendimiento obtenidos en las ejecuciones del proyecto y explica su variación. Para comparar todos los volúmenes bajo la función optimizada, repetir al menos tres veces cada tamaño de lote y documentar mediana y rango.

## Repositorio remoto

El proyecto está organizado como repositorio Git local y listo para conectarse a GitLab. Antes de publicarlo, revisar que solo incluya archivos del proyecto y que no contenga credenciales, datos personales ni archivos de respaldo de la base. Cree un proyecto vacío en GitLab desde la cuenta del equipo, agregue su URL como remoto y publique la rama principal. Añada el enlace del proyecto al informe final.

