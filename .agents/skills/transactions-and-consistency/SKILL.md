---
name: transactions-and-consistency
description: Use when the user writes multi-step database mutations, money transfers, "create X and Y together", or anywhere a partial failure leaves the DB in an inconsistent state. Covers when to use a transaction, isolation levels, optimistic vs pessimistic locking, idempotency for mutations.
---

# Transactions & Consistency

> A function that does two writes is one bug away from doing one. The DB-level transaction is the only thing that makes "all or nothing" actually true.

## When to use
- Writing two or more DB mutations that must succeed together
- Reading a value, computing on it, and writing it back (read-modify-write)
- Money/credit transfers, inventory decrements, balance updates
- "Create user + create profile + create default workspace" flows
- Anywhere a crash mid-function would leave inconsistent state

## When to skip
- Single-statement updates with no read-modify-write
- Pure read operations (use a snapshot or `READ COMMITTED` default)

## The rule

> **Wrap every multi-step write that must be atomic in a transaction. No exceptions for "it'll probably be fine."**

```ts
// BAD — second insert can fail; user exists with no profile
await db.user.create({ data: { email } })
await db.profile.create({ data: { userId, ... } })

// GOOD — both succeed or neither does
await db.$transaction(async (tx) => {
  const user = await tx.user.create({ data: { email } })
  await tx.profile.create({ data: { userId: user.id, ... } })
})
```

In Drizzle:
```ts
await db.transaction(async (tx) => { ... })
```

## The rules

### 1. Read-modify-write needs a transaction OR a conditional update.

```ts
// BAD — classic lost-update bug
const account = await db.account.findUnique({ where: { id } })
const newBalance = account.balance - amount
await db.account.update({ where: { id }, data: { balance: newBalance } })
// Two concurrent withdrawals both read 100, both write 60. The DB ends up at 60. We lost 40.

// GOOD #1 — atomic increment in the DB
await db.account.update({
  where: { id, balance: { gte: amount } },
  data: { balance: { decrement: amount } },
})

// GOOD #2 — transaction with row lock
await db.$transaction(async (tx) => {
  const acct = await tx.$queryRaw`SELECT balance FROM account WHERE id = ${id} FOR UPDATE`
  if (acct[0].balance < amount) throw new InsufficientFunds()
  await tx.account.update({ where: { id }, data: { balance: { decrement: amount } } })
})
```

### 2. Pick the right isolation level. Default is rarely enough for money.

| Level | Prevents | Use for |
|---|---|---|
| `READ COMMITTED` (Postgres default) | dirty reads | most reads |
| `REPEATABLE READ` | non-repeatable reads, phantom-ish | most reports & money flows |
| `SERIALIZABLE` | all anomalies | inventory, balances, "this can't possibly be wrong" |

```ts
await db.$transaction(async (tx) => { ... }, {
  isolationLevel: 'Serializable', // Prisma
})
```

`SERIALIZABLE` can fail with retry-able serialization errors — your code must handle them (see rule 6).

### 3. Optimistic vs pessimistic — pick deliberately.

**Optimistic** (version column / `WHERE version = ?`): cheap, scales well, fits low-contention. The retry is your job.

```ts
const updated = await db.doc.updateMany({
  where: { id, version: currentVersion },
  data: { content, version: { increment: 1 } },
})
if (updated.count === 0) throw new ConflictError() // user must reload
```

**Pessimistic** (`SELECT … FOR UPDATE`): blocks other writers; right when contention is real (inventory of 1, account balance, sequence numbers).

Default to optimistic. Reach for pessimistic when you've measured contention or the consequences of a lost update are unacceptable.

### 4. Keep transactions short.

```ts
// BAD — third-party API call inside a transaction holding row locks
await db.$transaction(async (tx) => {
  const order = await tx.order.create({ data })
  await stripe.charges.create(...)  // 800ms of network blocking the lock
  await tx.order.update(...)
})

// GOOD — split. Charge first (with idempotency), record after.
const charge = await stripe.charges.create({ idempotencyKey, ... })
await db.$transaction(async (tx) => {
  const order = await tx.order.create({ data: { ..., chargeId: charge.id } })
  await tx.invoice.create({ data: { orderId: order.id, ... } })
})
```

Long transactions = long locks = stalled writes for everyone touching the same rows.

### 5. Never call external APIs inside a transaction.

Same reason as rule 4 plus: the third-party call can succeed *and then your transaction can roll back*. You charged the customer; your DB has no record. Pattern: charge first with an idempotency key, store the result, then commit. Roll back by issuing a refund — not by hoping the external side undoes itself.

### 6. Handle serialization failures with a retry loop.

Under `SERIALIZABLE` (and sometimes `REPEATABLE READ`), Postgres raises `40001 serialization_failure` when conflicting tx histories can't be linearized. Retry the whole transaction:

```ts
async function withRetry<T>(fn: () => Promise<T>, max = 3): Promise<T> {
  for (let i = 0; i < max; i++) {
    try { return await fn() }
    catch (e: any) {
      if (e.code !== '40001' || i === max - 1) throw e
      await sleep(50 * 2 ** i)
    }
  }
  throw new Error('unreachable')
}
```

### 7. Idempotency for mutations that cross network boundaries.

If a mutation can be retried by the client (network hiccup, queue redelivery, double-click), the second call must not double-execute. Use an idempotency key (see `api-route-hardening`) keyed in the same DB so it's covered by the same transaction.

### 8. Multi-table reads for reports → snapshot.

A long report that reads from many tables needs a consistent point-in-time view, otherwise you'll sum invoices that exclude payments that exist. Use `REPEATABLE READ` or `SERIALIZABLE`, or take an explicit snapshot.

### 9. Distributed transactions are a trap.

Two-phase commit across services is brittle. The right answer for cross-service atomicity is **idempotent steps + retries + a saga / outbox pattern**. Pretend the network is unreliable (it is) and design each step to be safely retried.

### 10. The outbox pattern, in 5 lines.

When you need to "write to DB and emit an event together":

```ts
await db.$transaction(async (tx) => {
  await tx.order.create({ data })
  await tx.outboxEvent.create({ data: { type: 'order.created', payload: ... } })
})
// A separate worker reads from outboxEvent and publishes, marking each delivered.
```

Either both are committed (event will be delivered eventually) or neither is. No "we wrote the row but failed to emit the event."

## War story

A "credit + debit" between user wallets used two `update` calls back-to-back, no transaction. Process killed (Vercel cold-boot timeout) between them. Sender debited, receiver not credited. Money disappeared. Customer support spent two days reconstructing 14 transfers from logs and reconciling balances by hand. One `$transaction` wrapper would have rolled back the debit on failure.

## Quick checklist

- [ ] Multi-step writes wrapped in a transaction
- [ ] Read-modify-write uses atomic increment OR `FOR UPDATE` OR optimistic version check
- [ ] Money / inventory / counters use `SERIALIZABLE` (with retry) or atomic ops
- [ ] No external API calls inside a transaction
- [ ] Long-running work moved out of the tx
- [ ] Serialization failures retried with backoff
- [ ] Idempotency keys on retryable mutations
- [ ] Outbox pattern for "write + emit event" atomicity
