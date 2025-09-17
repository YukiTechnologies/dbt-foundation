{#
    star_from_relations
    Dynamically expands columns from a union of relations produced with dbt_utils.union_relations.
    Parameters:
        relations (list[Relation]): Relations to union
        relation_alias (string|false): Optional alias prefix for each column
        except (list[string]): Column names to exclude (case-sensitive)
    Notes:
        - Evaluated only at execution (guarded by `if execute`).
        - Ensure all relations share compatible column names to avoid null paddings.
#}
{%- macro star_from_relations(relations=[], relation_alias=False, except=[]) -%}

    {%- set union = dbt_utils.union_relations(relations=relations) -%}
    {%- set select_sql = 'select * from ' ~ union -%}
    {%- if execute -%}
        {%- set select_columns = dbt.get_columns_in_query(select_sql) -%}
        {%- for col in select_columns -%}
            {%- if col not in except -%}
                {%- if relation_alias %}{{ relation_alias }}.{% else %}{%- endif -%}{{ adapter.quote(col) }}
                {{ ", " if not loop.last -}}
            {%- endif -%}
    {%- endfor -%}
    {%- endif -%}

{%- endmacro -%}