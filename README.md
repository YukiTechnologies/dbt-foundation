## dbt Base Project

A production-ready starter for dbt (Snowflake focused) designed to help you move from zero to a maintainable analytics engineering workflow quickly.

## 1. Features At a Glance
- Snowflake query tagging for deep observability (JSON metadata on every query) — [`yuki-snowflake-dbt-tags`](https://github.com/YukiTechnologies/yuki-snowflake-dbt-tags)
- Dynamic column expansion across multiple relations (eliminate brittle `SELECT *`) — `macros/star_from_relations.sql`
- Orphaned object detection & safe cleanup (surface stale tables/views after renames/deletes) — `macros/list_orphaned_objects.sql`
- Automated quality gates before commit (parse checks, style, prevent hard-coded objects) — `.pre-commit-config.yaml`
- Schema-qualified (not database-qualified) refs for safe database cloning (let cloned DB resolve internally without hard-coding prod) — `macros/overrides/ref.sql`
- Clean schema naming (no env prefix concatenation; predictable schema layout) — `macros/overrides/generate_schema_name.sql`
- Curated utility packages: `dbt_utils`, `dbt_project_evaluator`, `codegen` — declared in `packages.yml`

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
Create or edit `~/.dbt/profiles.yml` (or use dbt Cloud project settings):
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
2. Rename the profile key in `profiles.yml` (and `profiles.example.yml`).
3. (Optional) Adjust dispatch if you introduce your project namespace for macro overrides.

## Feature Reference

### Query Tagging (yuki-snowflake-dbt-tags)
Adds structured JSON metadata (model, invocation_id, materialization, job context) to every Snowflake query. This lets you analyze performance, attribute cost, debug failed runs, and enrich lineage outside dbt docs with no model changes.

Install: Declared in `packages.yml` (already pinned). After `dbt deps`, tags apply automatically.

Example analysis query:
```sql
SELECT
  query_tag:dbt_model::string        AS model,
  avg(execution_time)                AS avg_ms,
  count(*)                           AS executions,
  max(query_tag:materialization)::string AS mat
FROM snowflake.account_usage.query_history
WHERE query_tag:dbt_model IS NOT NULL
GROUP BY 1,4
ORDER BY avg_ms DESC;
```

Notes:
- Account usage views lag a few minutes; use table functions for near‑real‑time.
- Plays nicely with other overrides due to dispatch ordering.

---

### Dynamic Column Expansion (star_from_relations)
File: `macros/star_from_relations.sql`

Generates an explicit column list across multiple relations (wrapper around `dbt_utils.union_relations`) so you avoid brittle `SELECT *`, keep deterministic ordering, and can exclude helper/system columns.

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

Emits only `schema.object` (no database) so a Snowflake database clone naturally resolves all refs to its own cloned copies without embedding the original database name.

Why this matters (clone scenario): After `CREATE DATABASE DEV_CLONE CLONE PROD_DB;`, cloned view SQL still mirrors the original text. Omitting the database keeps resolution local to `DEV_CLONE`, even if some upstream layers have not been rebuilt yet, reducing the chance of accidental reads from the production database.

Default vs override (illustrative):
```sql
-- Model
select * from {{ ref('stg_orders') }}

-- Upstream default (dbt may compile with or without database depending on context)
-- Overridden (this project): select * from ANALYTICS.STG_ORDERS;
```

Notes:
- For cross-database joins, explicitly qualify the other database where needed.
- If you intentionally need a prod object, hard-code the database (document why in code review).

Revert (remove override to allow dbt to qualify when appropriate):
```bash
git rm macros/overrides/ref.sql
dbt clean && dbt deps
```

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

---

### Utility Packages (packages.yml)
Curated set of widely-used macros & tooling.

| Package | Purpose |
|---------|---------|
| dbt_utils | Common modeling helpers (pivots, tests, surrogate keys) |
| dbt_project_evaluator | Automated project best-practice checks |
| codegen | Generate model & YAML scaffolding |

Upgrade:
Edit versions in `packages.yml` then run:
```bash
dbt deps
```

## 7. Query Observability
Snowflake query tags (via `yuki-snowflake-dbt-tags`) add JSON metadata (model, invocation_id, materialization, etc.).
Example performance query (note: Snowflake account usage views can lag by several minutes):
```sql
SELECT
  query_tag:dbt_model::string AS model,
  avg(execution_time) AS avg_ms,
  count(*) AS executions
FROM snowflake.account_usage.query_history
WHERE query_tag:dbt_model IS NOT NULL
GROUP BY 1
ORDER BY avg_ms DESC;
```

## 8. Code Quality Check (Summary)
`.pre-commit-config.yaml` hooks:
- `dbt-parse`
- `check-script-semicolon`
- `check-script-has-no-table-name`
Run manually:
```bash
pre-commit run --all-files
```

## 9. Daily Workflow
1. Define / update source YAML and model docs
2. Add / refine models (layering: sources → transformations → marts)
3. Add or update tests (`schema.yml`) and descriptions
4. Run `dbt build --select state:modified+` (tests + seeds + snapshots) or `dbt run` for models only
5. Review changes locally (`dbt ls --state ./ --select state:modified+`)
6. Commit (pre-commit ensures quality) & open PR (CI runs build)
7. Monitor query performance via tags; periodically run orphan cleanup macro

## 10. Upgrading
```bash
dbt --version
# Adjust versions in packages.yml
dbt deps
dbt run-operation project_evaluator
```

## 11. CI Example (GitHub Actions)
`.github/workflows/dbt.yml` (simplified):
```yaml
name: dbt Build
on: [pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install "dbt-snowflake>=1.8,<2.0" pre-commit
      - run: dbt deps
      - run: dbt build --select state:modified+ --state ./
```

## 13. Contributing
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

## 14. License
This project is licensed under the MIT License - see `LICENSE` for details.

---
Built to accelerate reliable analytics engineering. Adapt as needed for pure learning or enterprise hardening.
