## 🐧 dbt Base Project

A production-ready starter for dbt (Snowflake focused) designed to help you move from zero to a maintainable analytics engineering workflow quickly.

## 1. Features At a Glance
- Snowflake query tagging for deep observability (JSON metadata on every query) - [`yuki-snowflake-dbt-tags`](https://github.com/YukiTechnologies/yuki-snowflake-dbt-tags)
- Dynamic column expansion across multiple relations (like `dbt_utils.star` but for relations) - `macros/star_from_relations.sql`
- Orphaned object detection & safe cleanup (surface stale tables/views after renames/deletes) - `macros/list_orphaned_objects.sql`
- Automated quality checks before commit (prevent hard-coded objects, parse checks, semicolumns) - `.pre-commit-config.yaml`
- `ref()` override for safe database/schema cloning - `macros/overrides/ref.sql`
- Clean schema naming (no env prefix concatenation) - `macros/overrides/generate_schema_name.sql`
- Useful dbt-labs utility packages: [`dbt_utils`](https://github.com/dbt-labs/dbt-utils), [`dbt_project_evaluator`](https://github.com/dbt-labs/dbt-project-evaluator), [`codegen`](https://github.com/dbt-labs/dbt-codegen) - declared in `packages.yml`

### Quick Start (TL;DR)
```bash
git clone <your-repo-url>
cd dbt_base_project
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp profiles.example.yml ~/.dbt/profiles.yml  # edit credentials & roles
```

## 2. Prerequisites
- Python 3.10+ (virtual environment recommended)
- Snowflake role with: USAGE on database/warehouse, CREATE TABLE/VIEW privileges
- Ability to read `INFORMATION_SCHEMA.TABLES` (for orphan detection macro)
- Install adapter & tools:
```bash
pip install "dbt-snowflake>=1.8,<2.0" pre-commit
```

## 3. Clone & Install
```bash
git clone <your-repo-url>
cd dbt_base_project
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
dbt deps
pre-commit install
```

## 4. Configure Profiles
Create or edit `~/.dbt/profiles.yml` (or use dbt Cloud project settings).

Quick local template:
```bash
mkdir -p ~/.dbt
cp profiles.example.yml ~/.dbt/profiles.yml
```
Then edit credentials / roles:
```yaml
dbt_base_project:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      role: ANALYST_DEV
      database: DEV_DB
      warehouse: TRANSFORMING
      schema: analytics
      threads: 4
    prod:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      role: ANALYST_PROD
      database: PROD_DB
      warehouse: TRANSFORMING
      schema: analytics
      threads: 8
```
Export credentials securely (example only):
```bash
export SNOWFLAKE_ACCOUNT=xxx
export SNOWFLAKE_USER=xxx
export SNOWFLAKE_PASSWORD=xxx
```
Recommended: use a secrets manager or environment loading tool (1Password, AWS Secrets Manager, Vault, `direnv`) instead of committing secrets.

## 5. First Run
```bash
dbt debug          # Validate connection
dbt run            # Build sample models
dbt test           # Run tests
dbt docs generate && dbt docs serve
```

Rename Guidance:
1. Update your project `name` in `dbt_project.yml`.
2. Rename the profile key in `profiles.yml`.

## Feature Reference

### Query Tagging (yuki-snowflake-dbt-tags)
A Yuki dbt package that adds structured JSON metadata (model, invocation_id, materialization, job context) to every Snowflake query tag. This lets you analyze performance, attribute cost, debug failed runs, and enrich lineage outside dbt docs with no model changes.

Install: Declared in `packages.yml` (already pinned). After `dbt deps`, tags apply automatically.

Example analysis query:
```sql
SELECT parsed_query_tag:dbt_job::string         AS job
     , parsed_query_tag:dbt_model::string       AS model
     , parsed_query_tag:materialization::string AS materialization
     , AVG(execution_time)                      AS avg_ms
     , COUNT(*)                                 AS executions
  FROM snowflake.account_usage.query_history
  JOIN LATERAL (SELECT TRY_PARSE_JSON(query_tag) AS parsed_query_tag)
 WHERE parsed_query_tag:dbt_model IS NOT NULL
   AND start_time >= DATEADD(DAY, -7, CURRENT_DATE())
 GROUP BY ALL
 ORDER BY avg_ms DESC;
```

---

### Dynamic Column Expansion (star_from_relations)
File: `macros/star_from_relations.sql`

Generates an explicit column list across multiple relations (like `dbt_utils.star` but for relations, wrapper around `dbt_utils.union_relations`) so you avoid brittle `SELECT *`, keep deterministic ordering, and can exclude helper/system columns.

Parameters:
| Name | Type | Default | Description |
|------|------|---------|-------------|
| relations | list[Relation] | required | Relations to union / inspect |
| relation_alias | string/false | false | Prefix each column with alias |
| except | list[string] | [] | Columns to exclude from output |

Usage:
```jinja
{% set relations = [ref('fct_orders_current')
                  , ref('fct_orders_history')] %}

SELECT {{ star_from_relations(relations=relations, relation_alias='r') }}
  FROM ({{ dbt_utils.union_relations(relations=relations) }}) AS r
```

---

### Orphaned Object Detection (list_orphaned_objects)
File: `macros/list_orphaned_objects.sql`

Lists tables/views in the target database that are no longer managed by dbt.

Emits safe DROP / RENAME commands. This prevents confusion, stale data usage, and unnecessary storage cost after renames, deletions, or schema re‑orgs.

Common creation scenarios:
1. Rename: `dim_customers` -> `dim_customer` leaves old object.
2. Delete: Model removed from repo but table persists.
3. Move: Schema or folder re-org without cleanup.

Usage:
```bash
# List
dbt run-operation list_orphaned_objects --target prod
# Generate safe renames (quarantine)
dbt run-operation list_orphaned_objects --args '{output_rename_cmd: true}' --target prod
# Generate drop statements
dbt run-operation list_orphaned_objects --args '{output_drop_cmd: true}' --target prod
```

Tip: Stage rename commands for review before running destructive drops.

---

### Code Quality Check (.pre-commit-config.yaml)
Local git hooks enforce parse validity & style (shift problems left before CI). Key hooks:

| Hook | Purpose | Example Failure | Fix |
|------|---------|-----------------|-----|
| dbt-parse | Ensures models/macros parse | Missing comma / Jinja error | Correct SQL/Jinja syntax |
| check-script-semicolon | Blocks trailing semicolons in model SQL | `select 1 as x;` | Remove the `;` |
| check-script-has-no-table-name | Avoids hard-coded object refs | `select * from PROD_DB.ANALYTICS.FCT_ORDERS` | Use `{{ ref('fct_orders') }}` |

Install & run all hooks:
```bash
pre-commit install
pre-commit run --all-files
```

Run a single hook (example):
```bash
pre-commit run dbt-parse --all-files
```

Typical failure output snippet:
```text
check-script-has-no-table-name................................FAILED
- hook id: check-script-has-no-table-name
- files: models/example/my_first_dbt_model.sql
Hard-coded relation detected: PROD_DB.ANALYTICS.FCT_ORDERS
```

Updating hook versions:
```bash
pre-commit autoupdate
pre-commit run --all-files
```

Temporarily bypass (rare; prefer fixing):
```bash
SKIP=dbt-parse git commit -m "wip: spike"
```

---

### Schema-Qualified References (ref override)
File: `macros/overrides/ref.sql`

Compiles `select * from {{ ref('stg_orders') }}` <br>
to `select * from public.stg_orders` <br>
instead of `select * from dwh.public.stg_orders` <br> (only `schema.object` and no database). So a Snowflake database clone naturally resolves all refs to its own cloned copies without embedding the original database name.

Why this matters (clone scenario): After `CREATE DATABASE DEV_CLONE CLONE PROD_DB;`, cloned view SQL still mirrors the original text. Omitting the database keeps resolution local to `DEV_CLONE`, even if some upstream layers have not been rebuilt yet, reducing the chance of accidental reads from the production database.

---

### Clean Schema Naming (generate_schema_name)
File: `macros/overrides/generate_schema_name.sql`

Returns exactly the configured schema name (if provided) instead of prefix‑combining it with the target schema. Keeps dev/prod schemas identical for simpler permissioning & tooling configuration.

Usage:
```sql
{{ config(schema='analytics') }}
select 1 as dummy
```

Result: Object created in `<database>.ANALYTICS` rather than `<database>.<target_prefix>_analytics`.

Concrete example:
```yaml
# dbt_project.yml (excerpt)
name: cool_project
profile: cool_project
```

Default dbt behavior (no override) with target `dev` and model config `schema='analytics'` often yields a compiled relation like:
```
DEV_DB.DEV_ANALYTICS.MY_MODEL   # prefix added (project or target + provided schema)
```

With this override active the same model builds as:
```
DEV_DB.ANALYTICS.MY_MODEL       # without the added prefix
```

Benefit: Grants/monitoring tools only need to consider `ANALYTICS` in each database (no proliferation of environment-prefixed schemas).

---

### Utility Packages (packages.yml)
Curated set of widely-used macros & tooling.

| Package | Purpose |
|---------|---------|
| [dbt_utils](https://github.com/dbt-labs/dbt-utils) | Common modeling helpers (pivots, tests, surrogate keys) |
| [dbt_project_evaluator](https://github.com/dbt-labs/dbt-project-evaluator) | Automated project best-practice checks |
| [codegen](https://github.com/dbt-labs/dbt-codegen) | Generate model & YAML scaffolding |

Upgrade:
Edit versions in `packages.yml` then run:
```bash
dbt deps
```

## 6. Contributing
1. Maintain clear layering (sources → transformations → marts) and consistent naming.
2. Add / update tests & docs for every new or changed model or macro.
3. Run validation before pushing:
  ```bash
  pre-commit run --all-files
  dbt build --select state:modified+
  dbt run-operation project_evaluator || true
  ```
4. Document notable pattern changes in this README (append a short changelog entry if needed).
5. Avoid committing credentials or compiled artifacts (ensure `.gitignore` covers them).

## License
This project is licensed under the MIT License - see `LICENSE` for details.

---
Built to accelerate reliable analytics engineering. Adapt as needed for pure learning or enterprise hardening.
