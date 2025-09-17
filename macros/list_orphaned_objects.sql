{#
  list_orphaned_objects
  Purpose: Identify database tables/views in target database not represented in the current dbt graph.
  Output Modes (mutually exclusive):
    - default: OBJECT_TYPE SCHEMA.OBJECT
    - output_drop_cmd: DROP statements
    - output_rename_cmd: RENAME statements adding `_to_delete_` prefix (safer soft-delete)
  Usage:
    dbt run-operation list_orphaned_objects --target prod
    dbt run-operation list_orphaned_objects --args '{output_drop_cmd: true}' --target prod
    dbt run-operation list_orphaned_objects --args '{output_rename_cmd: true}' --target prod
  Requirements:
    - Source definition for information schema (see README `bi_information_schema`).
    - Adequate privileges to read information_schema.tables.
  Safety: Commands are printed only—never executed automatically.
#}

{% macro list_orphaned_objects(output_drop_cmd = false, output_rename_cmd = false) %}

  {% do log("", True) %}
  {% do log("Searching for orphaned tables/views...", True) %}
  {% do log("Using target profile: " ~ target.name ~ " (database: " ~ target.database ~ ").", True) %}

  {% set query %}
  SELECT REPLACE(table_type, 'BASE ', '') AS object_type
       , table_schema                     AS object_schema
       , table_name                       AS object_name
    FROM {{ source('target_db_information_schema', 'tables').include(database=false) }}
   WHERE table_schema <> 'INFORMATION_SCHEMA'
     AND object_name <> 'DATA_REFRESH_TIME'
   ORDER BY table_schema, table_type, table_name
  {% endset %}

  {% set query_result = run_query(query) %}
  {% set db_objects = [] %}
  {% for row in query_result.rows %}
    {% set object_full_name = row.OBJECT_TYPE ~ ' ' ~ row.OBJECT_SCHEMA ~ '.' ~ row.OBJECT_NAME %}
    {% set drop_cmd = 'DROP ' ~ object_full_name ~ ';' %}
    {% set rename_cmd = 'ALTER ' ~ object_full_name ~ ' RENAME TO ' ~ row.OBJECT_SCHEMA ~ '._to_delete_' ~ row.OBJECT_NAME ~ ';' %}
    {% set object_output = drop_cmd if output_drop_cmd else rename_cmd if output_rename_cmd else object_full_name %}
    {% do db_objects.append({"object_name": row.OBJECT_SCHEMA ~ '.' ~ row.OBJECT_NAME, "object_output": object_output }) %}
  {% endfor %}

  {% set models = [] %}
  {% for node in graph.nodes.values() | selectattr("resource_type", "equalto", "model") | list
               + graph.nodes.values() | selectattr("resource_type", "equalto", "seed")  | list  %}
      {% do models.append((node.config.schema or target.schema).upper() ~ '.' ~ node.alias.upper()) %}
  {% endfor %}

  {% set orphaned = db_objects | rejectattr('object_name', 'in', models) | map(attribute='object_output') | list %}
  {% do print(orphaned | join('\n')) %}

{% endmacro %}
