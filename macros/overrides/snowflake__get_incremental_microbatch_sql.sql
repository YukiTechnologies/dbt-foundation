{#
    snowflake__get_incremental_microbatch_sql (override)
    Purpose: Make a microbatch batch reload atomic for readers.
    Problem: Upstream dbt-snowflake runs the batch's delete and insert as two autocommits, so the batch's
    time window is missing for every reader until the insert lands (minutes if the insert computes from a view).
    Behavior: When the model opts in, run delete+insert in one EXECUTE IMMEDIATE script block that commits
    together, or rolls back and re-raises. The rollback matters: a failed insert must not leave a transaction
    open on the connection, where the next DDL would commit the delete.
    View-backed batches keep upstream's unwrapped SQL, since wrapping them would hold the delete's table lock
    for the whole model query. Iceberg targets (externally managed ones allow autocommit only) and SQL containing $$ also keep it.
    Usage: opt in with tmp_relation_type='table' (or 'transient') on the microbatch model.
    Based on: dbt-snowflake macros/materializations/incremental/merge.sql
#}
{% macro snowflake__get_incremental_microbatch_sql(arg_dict) %}
    {%- set target = arg_dict["target_relation"] -%}
    {%- set source = arg_dict["temp_relation"] -%}
    {%- set dest_columns = arg_dict["dest_columns"] -%}
    {%- set incremental_predicates = [] if arg_dict.get('incremental_predicates') is none else arg_dict.get('incremental_predicates') -%}

    {#-- Add additional incremental_predicates to filter for batch --#}
    {% if model.batch and model.batch.event_time_start -%}
        {% do incremental_predicates.append("DBT_INTERNAL_TARGET." ~ model.config.event_time ~ " >= to_timestamp_tz('" ~ model.config.__dbt_internal_microbatch_event_time_start ~ "')") %}
    {% endif %}
    {% if model.batch and model.batch.event_time_end -%}
        {% do incremental_predicates.append("DBT_INTERNAL_TARGET." ~ model.config.event_time ~ " < to_timestamp_tz('" ~ model.config.__dbt_internal_microbatch_event_time_end ~ "')") %}
    {% endif %}
    {% do arg_dict.update({'incremental_predicates': incremental_predicates}) %}

    {%- set dest_cols_csv = get_quoted_csv(dest_columns | map(attribute="name")) -%}
    {% set delete_sql -%}
    delete from {{ target }} DBT_INTERNAL_TARGET
    where (
    {% for predicate in incremental_predicates %}
        {%- if not loop.first %}and {% endif -%} {{ predicate }}
    {% endfor %}
    )
    {%- endset %}
    {% set insert_sql -%}
    insert into {{ target }} ({{ dest_cols_csv }})
    (
        select {{ dest_cols_csv }}
        from {{ source }}
    )
    {%- endset %}

    {#-- Wrap only when opted in with tmp_relation_type table/transient. Iceberg targets (externally managed ones allow autocommit only) and SQL containing $$ (would break the dollar-quoted block) keep upstream behaviour. --#}
    {% if config.get('tmp_relation_type') in ('table', 'transient') and not target.is_iceberg_format and '$$' not in (delete_sql ~ insert_sql) %}
    execute immediate $$
    begin
        begin transaction;
        {{ delete_sql }};
        {{ insert_sql }};
        commit;
    exception
        when other then
            rollback;
            raise;
    end;
    $$
    {% else %}
    {{ delete_sql }};
    {{ insert_sql }}
    {% endif %}
{% endmacro %}
