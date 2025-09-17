{#
    ref (override)
    Purpose: Emit schema-qualified (NOT database-qualified) references so a cloned database naturally resolves to its own cloned objects without hard‑coding the original database name.
    Behavior: Delegates to builtins.ref then calls .include(database=false).
    Rationale: After a Snowflake database clone, leaving database off encourages all resolution to stay inside the clone; upstream layers rebuilt later will still point at clone-local objects.
    Caveat: Alters a core primitive; remove this file to restore upstream behavior (which may sometimes include database qualification depending on context).
    Supports: ref('model'), ref('package','model'), ref('model', version=n)
    Based on: https://docs.getdbt.com/reference/dbt-jinja-functions/builtins
#}
{% macro ref() %}
  {% set version = kwargs.get('version') or kwargs.get('v') %}
  {% set packagename = none %}
  {%- if (varargs | length) == 1 -%}
    {% set modelname = varargs[0] %}
{%- else -%}
    {% set packagename = varargs[0] %}
    {% set modelname = varargs[1] %}
{% endif %}
-- call builtins.ref based on provided positional arguments
{% set is_db_included = false %}
{% if packagename is not none %}
    {% do return(builtins.ref(packagename, modelname, version=version).include(database=is_db_included)) %}
{% else %}
    {% do return(builtins.ref(modelname, version=version).include(database=is_db_included)) %}
{% endif %}
{% endmacro %}
