{#
    generate_schema_name
    Returns the explicitly provided custom schema (trimmed) or the target schema.
    Purpose: Avoid default concatenation patterns so environments share identical logical schema names.
    Parameters:
        custom_schema_name (string|none): Schema passed via config(schema='...')
        node: The dbt node (unused, kept for signature compatibility)
    Usage:
        {{ config(schema='analytics') }} -> renders objects in <database>.analytics
#}
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}

        {{ default_schema }}

    {%- else -%}

        {{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
