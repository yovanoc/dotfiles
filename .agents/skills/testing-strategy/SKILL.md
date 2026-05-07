---
name: testing-strategy
description: Use when the user writes tests, asks "should I write a test for this?", chooses between unit/integration/e2e, sets up a test runner, or hits flaky tests. Covers what to integration-test vs unit-test, testing the contract not the implementation, fakes vs mocks, and flaky-test triage.
---

# Testing Strategy

> Tests are not a moral virtue. They are an investment with a return: catch regressions, document behavior, enable refactors. Write the tests that pay back; skip the ones that don't.

## When to use
- Writing tests for new code
- Asking "should I write a test for this?"
- Choosing test type for a feature
- Setting up the test runner / CI
- Diagnosing a flaky test
- Reviewing a PR's test coverage

## When to skip
- Throwaway scripts and prototypes you'll delete
- One-off internal tooling

## The mental model: test the contract

Test **what callers depend on**, not how it's done internally. If a refactor preserves behavior but rewrites every line, the tests should still pass. If they don't, they were testing the wrong thing.

```ts
// BAD — tests the implementation
expect(spy).toHaveBeenCalledWith({ format: 'iso', tz: 'UTC' })

// GOOD — tests the behavior callers see
expect(formatDate(new Date('2026-05-07'))).toBe('2026-05-07')
```

## The pyramid (still right, just adapted)

| Layer | Speed | What it covers | Volume |
|---|---|---|---|
| **Unit** | <1ms | pure logic, edge cases of a single function | many |
| **Integration** | 10–500ms | function + its real DB / real Redis / real auth | medium |
| **E2E** | seconds | full flows: signup → checkout, in a real browser | few |

Run unit on every save, integration on every push, E2E on every PR. **Do not invert this.** A 12-minute test suite kills feedback.

## The rules

### 1. Default to integration tests for backend code.

A unit test of a function that just calls Drizzle and Zod tells you nothing — it tests the function's *invocation* of mocks, not its behavior. Integration tests with a real Postgres (Testcontainers, ephemeral schema, or `pglite` for blazing speed) are where bugs actually live.

```ts
// vitest + Testcontainers
import { GenericContainer } from 'testcontainers'
beforeAll(async () => {
  pg = await new GenericContainer('postgres:16').withExposedPorts(5432).start()
  // run migrations against this DB
})
```

### 2. Mocks lie. Use real things or fakes; mocks are the last resort.

| | What it is | When |
|---|---|---|
| **Real** | actual implementation in test | DB, Redis, your own code |
| **Fake** | a working alternative impl (in-memory queue, fake clock) | when "real" is too slow/external |
| **Stub** | returns canned data | trivial values |
| **Mock** | asserts on how it was called | last resort, brittle |

Mocks couple your tests to implementation details. Every refactor breaks a mock-heavy suite.

### 3. Test the boundaries you control. Trust libraries and frameworks.

Don't test that `useState` updates state. Don't test that Drizzle's `eq()` builds the right SQL. Test **your function** that uses these, against the input/output your callers see.

### 4. Each test: arrange, act, assert. Independent and ordered-doesn't-matter.

```ts
it('rejects expired sessions', async () => {
  // arrange
  const session = await createSession({ expiresAt: pastDate() })
  // act
  const result = await validateSession(session.id)
  // assert
  expect(result.ok).toBe(false)
})
```

If test B depends on test A having run first, the suite is fragile. Each test sets up its own world (transaction rollback, fresh DB, factory functions).

### 5. Fast resets, not isolated test runners.

For Postgres integration tests:
- **Best**: each test in a transaction, rolled back at end. Sub-millisecond reset.
- **Good**: truncate tables between tests.
- **Bad**: drop & recreate DB per test.

### 6. E2E: cover the **golden path** + a couple of critical errors. Not coverage.

Playwright/Cypress for: signup, login, the core action your product exists to do, payment, data export. **Not for**: every form field, every empty state. Those go in component / integration tests.

A green E2E suite that takes 90 minutes to run gets disabled within a quarter. Keep it under 5.

### 7. Determinism > everything. A flaky test is a bug.

```ts
// BAD — depends on real time
expect(post.createdAt).toBeLessThan(new Date())

// GOOD — inject the clock
expect(post.createdAt).toEqual(fixedNow)
```

Sources of flake:
- Real time (`Date.now()`, `setTimeout`) — use a fake clock (`vi.useFakeTimers()`)
- Real network — use real local services or MSW for HTTP mocking
- Order dependence — tests share state they shouldn't
- Race conditions in the code under test — **fix the code**, don't add `await sleep(100)`

### 8. The "I added a `sleep()` to fix the flake" rule.

If you added a `sleep()`, you patched a symptom. Find the actual race. `Promise.all`, missing await, async event you didn't wait for — there's a real reason.

### 9. Snapshot tests: yes for stable output, no for everything.

Snapshots are great for:
- Generated API responses where the schema rarely changes
- Stable component renders with deterministic input

Snapshots are bad for:
- Anything with timestamps, IDs, randomness (use serializers to redact, or test specific fields)
- Big trees where every change "fix" is a thousand-line snapshot diff that no one reads

### 10. CI signal beats local signal.

Tests must pass on the CI box, not just on yours. Common reasons CI fails when local passes:
- Different timezone (`TZ=UTC` in CI, but you're in `America/Los_Angeles`)
- Different filesystem (case-sensitive on Linux, case-insensitive on Mac)
- Tests racing because CI parallelism > local
- A test that creates a file in cwd

**Fix**: pin timezone, run case-sensitive locally, run with the same parallelism as CI.

### 11. Coverage % is the wrong number to watch.

Coverage tells you what *ran* under test, not whether the test caught anything. A 95% coverage suite that asserts nothing is worthless. Watch:
- **Mutation testing** (`stryker-mutator`) for "do tests catch bugs?"
- **Bug recurrence rate** — bugs you've fixed and shipped a regression test for shouldn't recur

### 12. Type tests for type-heavy code.

```ts
import { expectTypeOf } from 'vitest'
expectTypeOf<UserInput>().toMatchTypeOf<{ email: string; age: number }>()
```

Generic-heavy library code earns type tests; everyday app code usually doesn't.

## What "good" looks like

| Code shape | Default test |
|---|---|
| Pure function with branches | unit, table-driven over inputs |
| Route handler / Server Action | integration with real DB |
| React component with logic | component test (Testing Library), focus on behavior |
| End-to-end user journey | one E2E per flow, golden path + 1-2 errors |
| Generic types | type-level test |

## War story

A startup's CI suite grew to 14 minutes and 800 tests, mostly mock-heavy unit tests of route handlers. They refactored from REST to tRPC, broke ~600 tests (all the mocks), and the team gave up on tests for a quarter. The replacement: 80 integration tests against a real Postgres (Testcontainers), 4 minutes total, caught more regressions than the previous 800 ever had.

## Quick checklist

- [ ] Tests exercise behavior, not implementation
- [ ] Backend logic uses integration tests (real DB) by default
- [ ] Mocks only as last resort; prefer real or fake
- [ ] Each test self-sufficient (no order dependence)
- [ ] Fast reset (transaction rollback) between integration tests
- [ ] E2E covers golden path; doesn't try to cover everything
- [ ] No `sleep()` band-aids; flakes are bugs to fix
- [ ] Time / random / network injected, not real
- [ ] Coverage isn't the goal; bug recurrence is
