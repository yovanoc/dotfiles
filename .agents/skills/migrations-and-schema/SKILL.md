---
name: migrations-and-schema
description: Use when the user edits a schema file (schema.prisma, drizzle schema), generates a migration, writes ALTER TABLE / DROP COLUMN / ADD CONSTRAINT, renames a column, or changes a type. Catches table locks on big tables, breaking deploys, missing backfills, no rollback path.
---

# Migrations & Schema Changes

> A migration is the part of your code that runs in production exactly once, with no test environment that has the same data, while users are using the system. Treat it with appropriate paranoia.

## When to use
- Editing `schema.prisma`, Drizzle schema, or any DDL file
- Generating a migration (`prisma migrate dev`, `drizzle-kit generate`)
- Writing raw `ALTER TABLE` / `CREATE INDEX` / `DROP COLUMN`
- Renaming a column or table
- Changing a column type
- Adding a `NOT NULL` constraint to an existing column

## When to skip
- Local-only schema changes you'll squash before merging
- Pre-launch projects with zero production data

## The two rules

1. **Expand before contract.** Add the new shape; deploy code that handles both shapes; remove the old shape after.
2. **Deploy code and migration in compatible order.** The running app must work *before* the migration, *during* the migration, and *after* the migration.

Get either wrong → outage.

## The patterns

### 1. Adding a non-nullable column → 3 deploys

```sql
-- ❌ One-shot: ALTER TABLE user ADD COLUMN tier text NOT NULL DEFAULT 'free';
-- On a big table this either takes a long lock OR (Postgres 11+) is fast for constants but
-- still risky. The clean pattern works regardless of DB version and table size:

-- Deploy 1: add nullable column, deploy code that writes both old + new shape
ALTER TABLE "user" ADD COLUMN "tier" text;

-- Deploy 2 (or background job): backfill in batches
UPDATE "user" SET tier = 'free' WHERE tier IS NULL;
-- (batch with LIMIT + loop on huge tables to avoid bloat & long transactions)

-- Deploy 3: enforce NOT NULL + default
ALTER TABLE "user" ALTER COLUMN tier SET NOT NULL;
ALTER TABLE "user" ALTER COLUMN tier SET DEFAULT 'free';
```

### 2. Renaming a column → never rename. Add + migrate + remove.

```sql
-- ❌ ALTER TABLE user RENAME COLUMN name TO full_name;
-- The old code still expects `name`. The instant the migration runs, every server pod
-- using `name` errors. There is no version of "deploy first or migrate first" that works.

-- ✅ Pattern:
-- 1. Add `full_name` column (nullable)
-- 2. Deploy code that writes BOTH `name` and `full_name`
-- 3. Backfill `full_name = name` for old rows
-- 4. Deploy code that reads `full_name`, falls back to `name`
-- 5. Deploy code that reads/writes only `full_name`
-- 6. Drop `name`
```

Slow. Painful. The alternative is downtime.

### 3. Dropping a column → wait one deploy.

The old code may still reference the column. Drop only after a deploy where no code references it has shipped to production.

```sql
-- Deploy N: remove all references in code
-- Deploy N+1: ALTER TABLE x DROP COLUMN y;
```

### 4. Adding an index on a big table → CONCURRENTLY.

```sql
-- ❌ Locks the table for writes
CREATE INDEX idx_message_user ON message(user_id);

-- ✅ No write lock; takes longer to build
CREATE INDEX CONCURRENTLY idx_message_user ON message(user_id);
```

`CONCURRENTLY` cannot run inside a transaction — most migration tools wrap migrations in a tx. You'll need to mark this migration as non-transactional or run the index creation outside the migration framework.

### 5. Adding a foreign key on a big table → NOT VALID, then VALIDATE.

```sql
-- ✅ Two-step: instant, then slow but online
ALTER TABLE order ADD CONSTRAINT fk_order_user
  FOREIGN KEY (user_id) REFERENCES "user"(id) NOT VALID;
ALTER TABLE order VALIDATE CONSTRAINT fk_order_user;
```

The `NOT VALID` step locks briefly and applies the constraint to new rows. `VALIDATE CONSTRAINT` scans existing rows without blocking writes.

### 6. Changing a column type → expand and contract.

Same pattern: add new column, dual-write, backfill, switch reads, drop old.

The shortcut `ALTER COLUMN ... TYPE ...` is sometimes safe (e.g., `varchar(50)` → `varchar(100)`), often dangerous (numeric widening rewrites the table), and sometimes catastrophic (any change requiring rewriting all rows takes an `ACCESS EXCLUSIVE` lock — full downtime on a big table).

When unsure: expand and contract.

### 7. Dropping a table → rename it first.

```sql
-- Today
ALTER TABLE deprecated_thing RENAME TO _deprecated_thing_2026_05;

-- Two weeks later, when you're sure nothing uses it
DROP TABLE _deprecated_thing_2026_05;
```

Reversibility for two weeks is cheap. Restoring a dropped table from backup at 2am is not.

### 8. Backfills on big tables → batch with delays.

```sql
-- ❌ One huge UPDATE
UPDATE order SET region = customer_region(customer_id);
-- Long transaction → table bloat, replication lag, vacuum can't run.

-- ✅ Loop in app code, in batches
-- WHILE EXISTS (...):
--   UPDATE order SET region = ...
--     WHERE id IN (SELECT id FROM order WHERE region IS NULL LIMIT 1000);
--   COMMIT; sleep 100ms
```

Run as a one-shot script, not a migration step. Migrations should be fast and atomic.

### 9. Always have a down migration. Even if you'll never run it.

Writing the rollback forces you to think about reversibility before applying. If a migration is irreversible (data loss), say so explicitly and require manual override.

### 10. Run migrations *before* deploying app code that depends on them.

For "additive" migrations (new column, new index): migrate first, then deploy.
For "removing" migrations: deploy code that no longer uses the column first, then migrate.
This is exactly the expand/contract rule, applied at the deploy level.

## Tools that help

- **Squawk** (`paulgb/squawk`) — lints migrations for unsafe patterns. Add to CI.
- **pg_repack** — rewrites bloated tables online.
- **`SET lock_timeout = '2s'`** at the start of a migration — prevents the migration from being the thing that blocks production.

## War story

A 30M-row migration: `ALTER TABLE orders ADD COLUMN promo_code text NOT NULL DEFAULT '';`. Looked harmless. Took an `ACCESS EXCLUSIVE` lock for 11 minutes during peak traffic while every backend instance backed up waiting for the lock, then ran the table rewrite. 11 minutes of total checkout outage. The fix was the 3-step pattern above, but learned at the wrong time.

## Quick checklist

- [ ] Migration is **additive**, or paired with a "drop" deploy that comes later
- [ ] App code works against both old and new schema during the deploy window
- [ ] `NOT NULL` added in 3 steps (nullable → backfill → enforce)
- [ ] Renames are expand-and-contract, never one-shot
- [ ] Indexes on big tables use `CREATE INDEX CONCURRENTLY`
- [ ] Foreign keys on big tables use `NOT VALID` + `VALIDATE`
- [ ] Backfills batched in app code, not in a single `UPDATE`
- [ ] Down migration exists (or irreversibility is explicit)
- [ ] `SET lock_timeout` set at migration start
- [ ] CI lints migrations (Squawk or equivalent)
