---
name: index-auditor
description: Find missing and unused database indexes in a Rails application, using foreign keys, query patterns in the codebase, and Postgres statistics. Use when queries are slow, when sequential scans show up on large tables, after a schema has grown organically, or when the user asks about database indexing or N+1 and query performance.
---

# Index Auditor

Finds indexes a Rails schema should have and does not — and, just as usefully,
indexes it has and does not need.

Runs as an **audit**, not a fixer. It produces a ranked list with evidence and a
migration for each candidate. Adding indexes blindly is its own performance
problem, so the decision stays with a human.

## Why this needs care

Every index makes writes slower and consumes storage. An application with an
index on every column is not fast — it is slow in a different place, and harder
to reason about. The goal is the smallest set that covers the queries that
actually run.

So each finding needs **evidence**, not a hunch.

## Step 1 — unindexed foreign keys

The highest-yield check, and the most common gap. Rails adds an index with
`add_reference ... index: true` and with `t.references`, but foreign keys
created by hand, added in early migrations, or introduced before the convention
settled frequently have none. Every `belongs_to` join and every
`has_many` lookup then scans.

```sql
SELECT c.conrelid::regclass AS table_name,
       a.attname            AS column_name
FROM   pg_constraint c
JOIN   pg_attribute  a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE  c.contype = 'f'
AND    NOT EXISTS (
         SELECT 1 FROM pg_index i
         WHERE i.indrelid = c.conrelid
         AND   a.attnum = i.indkey[0]
       );
```

Cross-check against `db/schema.rb` — a `belongs_to` in a model with no matching
index is the same finding arriving from the other direction.

## Step 2 — query patterns in the code

Grep for columns the application filters, sorts, or joins on:

- `where(...)` with a consistent column, especially in scopes and default scopes
- `order(...)` on anything not already indexed — sorting an unindexed column on
  a large table is a sort of the whole table
- `find_by_*`, and any column used for lookup that is not the primary key
- Polymorphic associations, which need a **composite** index on
  `(type, id)`, not two single-column indexes
- `where(...).order(...)` combinations — these want one composite index in
  filter-then-sort order, not two separate ones

**Column order in a composite index matters.** `(account_id, created_at)` serves
`WHERE account_id = ? ORDER BY created_at` well; the reverse serves it badly.
State the intended order and the query it is for.

## Step 3 — ask the database what actually happened

Code inspection finds candidates; production statistics find truth.

**Tables being scanned sequentially:**

```sql
SELECT relname, seq_scan, seq_tup_read, idx_scan
FROM   pg_stat_user_tables
WHERE  seq_scan > 0
ORDER  BY seq_tup_read DESC
LIMIT  20;
```

High `seq_tup_read` with low `idx_scan` on a large table is a strong signal. On
a small table it is meaningless — Postgres will correctly prefer a sequential
scan, and adding an index there makes things worse.

**Slow queries**, if `pg_stat_statements` is available:

```sql
SELECT query, calls, mean_exec_time, rows
FROM   pg_stat_statements
ORDER  BY mean_exec_time DESC
LIMIT  20;
```

**Indexes nobody uses** — the reverse audit, and frequently the more valuable
half:

```sql
SELECT relname AS table, indexrelname AS index, idx_scan
FROM   pg_stat_user_indexes
WHERE  idx_scan = 0
ORDER  BY pg_relation_size(indexrelid) DESC;
```

Zero scans since the last statistics reset means the index is pure write
overhead. Confirm the reset window before recommending removal, and never drop a
unique index that is enforcing a constraint.

## Step 4 — prove it with EXPLAIN

For every candidate, capture the plan before and after:

```ruby
puts Model.where(...).explain(analyze: true)
```

A finding without a before/after plan is a guess. If the plan does not improve —
and on small tables it often will not — **drop the candidate and say why.** A
rejected candidate with evidence is a useful result.

## Step 5 — write migrations that are safe in production

Creating an index locks the table against writes for the duration. On anything
large this is an outage.

```ruby
class AddIndexToOrdersAccountId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :orders, :account_id, algorithm: :concurrently
  end
end
```

`algorithm: :concurrently` requires `disable_ddl_transaction!` — they always
travel together. Concurrent builds are slower and can fail, leaving an invalid
index behind; note that a failed build needs cleaning up before retrying.

**One index per migration.** They are independently revertable and independently
blamable.

## Rules

- **Never add an index without evidence.** Name the query or statistic behind it.
- **Never add indexes in bulk.** Each one is a write-performance cost.
- **Never build an index non-concurrently on a large table.**
- **Do not recommend indexes on small tables.** Sequential scan is correct there.
- **Do not drop unique indexes** that enforce a constraint, however unused they
  look.
- **This skill does not fix N+1 queries.** Those need eager loading, not
  indexing — a missing `includes` is a different defect, and an index makes the
  symptom smaller while leaving the cause. Report N+1 separately if found.

## Reporting

For each recommendation: the table and column(s), including composite order and
the query it serves; the evidence (unindexed FK, query pattern, or statistic);
before/after `EXPLAIN` output; estimated table size and whether a concurrent
build is required; and the migration.

Then report **candidates rejected and why**, and **unused indexes** proposed for
removal with their size.

Close with the count added, rejected, and removed. "Six missing indexes found
and added, four candidates rejected as unnecessary" is a more trustworthy result
than a long list of additions.
