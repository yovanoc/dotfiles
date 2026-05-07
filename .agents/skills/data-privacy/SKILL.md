---
name: data-privacy
description: Use when the user stores user data, PII, payment info, health/biometric data, builds export/delete features, signs up for data processors, configures backups, or designs cross-border data flows. Covers encryption at rest/transit, deletion paths, audit logs, what to never log, and minimum-data principles.
---

# Data Handling & Privacy

> Every piece of user data you store is a liability. The cheapest data is the data you didn't collect; the second cheapest is the data you deleted on schedule.

## When to use
- Designing a new schema that stores user-attributable data
- Adding a "store this preference / address / payment / message" feature
- Building data export ("download my data")
- Building data deletion ("delete my account")
- Reviewing what gets logged (see `observability`)
- Picking a third-party processor (sub-processors get your data too)
- Working with PII, PHI, payment data, biometrics, location, minors' data

## When to skip
- No user-attributable data (truly public, anonymous content)

## The mental model

Data has a lifecycle: **collect → store → use → share → retain → delete**. Privacy work is making each stage deliberate. "We collected it because the form had a field" is not a reason. "We retain it because we never thought about it" is the most common reason data leaks.

## The rules

### 1. Minimize. Don't collect what you don't need.

Every field you ask for is a liability. Birth date for a B2B SaaS? Probably not. Phone for a free-tier user? Only if you're going to call them.

```ts
// BAD — full address for a digital-only product
const Profile = z.object({
  fullName: z.string(),
  street: z.string(),
  city: z.string(),
  state: z.string(),
  zip: z.string(),
  dob: z.string(),
})

// GOOD — collect what the product needs
const Profile = z.object({
  displayName: z.string(),
  email: z.string().email(),
})
```

### 2. Encrypt in transit. Always.

`https` only. HSTS. Modern TLS. No exceptions for "internal" traffic that crosses the public internet (Vercel ↔ Supabase ↔ Upstash all cross networks).

For internal service-to-service, use mTLS or signed requests. "We're inside the VPC" is not encryption.

### 3. Encrypt at rest. Application-level for sensitive fields.

Disk-level encryption (Postgres TDE, AWS RDS encryption) protects against stolen disks. It does **nothing** against a compromised app or DB credential — the DB decrypts transparently for any authenticated query.

For high-sensitivity fields (SSNs, government IDs, health data, full PII), encrypt at the application layer:

```ts
// Encrypted column: stored as ciphertext, decrypted only by the app with the key
const encrypted = await encrypt(ssn, env.PII_DATA_KEY)
await db.user.update({ data: { ssnEncrypted: encrypted } })
```

Use a managed KMS (AWS KMS, GCP KMS, Cloud HSM) for the key. Rotate it.

### 4. Hash, don't encrypt, when you only need to compare.

If you only need to check "does this email exist in our system?", you may not need to *store* the email — store a hash for comparison. Same for IP addresses kept for abuse detection: hash them with a per-tenant salt.

For passwords specifically: argon2id (see `auth-and-sessions`). Never reversible.

### 5. PCI: don't touch card data unless you have to.

For payment forms, use Stripe Elements / Checkout / Payment Sheet — your servers never see the PAN. The card data flows browser → Stripe directly; you receive a token. This is the difference between "we follow some PCI rules" and "we're 99% out of scope."

If you must handle card data: full PCI DSS audit, ASV scans, network segmentation. Almost never the right answer for a startup.

### 6. Audit log every access to sensitive data.

Who, what, when, why. Append-only. Tamper-evident if possible.

```ts
await db.auditLog.create({
  data: {
    actorUserId: session.userId,
    action: 'export_users',
    resourceType: 'user',
    resourceId: targetUserId,
    metadata: { reason: req.body.reason },
    ip: hashIp(req.ip),
    at: new Date(),
  },
})
```

When something goes wrong (or a regulator asks), you can answer "who looked at this?" Audit logs go to a different store, with different access, ideally write-only from the app.

### 7. The deletion rule: actually delete. Or have a real reason not to.

GDPR Article 17, CCPA, and most regional laws give users a right to deletion. "Soft-delete forever" is not deletion — it's hiding.

Deletion path:
- Hard-delete from primary DB (or anonymize: replace PII with `[deleted]`, keep the row's referential shell if other systems depend on its ID)
- Delete from search indexes (Algolia, Meilisearch, OpenSearch)
- Delete from caches (Redis, CDN)
- Delete from analytics if scoped to identity (PostHog, Amplitude)
- Delete from emails-out-of-band (transactional providers retain logs)
- Delete from backups eventually (or document retention period clearly)
- Delete from logs (or set TTL such that logs age out)
- Tell sub-processors who hold the data downstream

Test the path end-to-end before launch.

### 8. Export rule: structured, machine-readable, complete.

A user export is JSON / CSV / a zip — usable, not "log into a portal." Include everything user-attributable: profile, content, settings, audit log they're entitled to. Don't include other users' data even if it's adjacent (a comment on someone else's post mentions them, redact).

### 9. Logs are PII. Default to redacting.

What never goes in logs:
- Passwords (obvious; surprisingly common)
- Bearer tokens, API keys, session cookies — strip from `headers`
- Full request bodies on `POST` to auth/payment endpoints
- Email addresses unless redacted (`u***@d***.com`) or explicitly required for the log's purpose
- Full names, phone numbers, addresses, government IDs — never

Configure redaction at the logger level (Pino `redact`, Logtape filter), not per-call. See `observability`.

### 10. Cross-border data: know where the bytes live.

GDPR (EU), Schrems II (EU↔US), UK DPA, Brazil LGPD, India DPDP, China PIPL — each restricts where personal data can be stored or transferred. Practically:
- Pick a primary region for storage (`eu-west-1`, `us-east-1`)
- Pin databases / caches / file storage to that region
- For users in restricted regions, ensure the data path stays within the region (data residency)
- Document sub-processors and where each holds data (Stripe, Resend, Vercel, Upstash, etc.)

If you have any EU users: a Data Processing Addendum (DPA) is the table-stakes contract. Most processors offer one — sign it.

### 11. Backups are data too.

A "delete my account" that doesn't reach backups is a partial deletion. Either:
- Document a clear retention window for backups (e.g., 30 days), so deleted data ages out predictably
- Use point-in-time recovery with deletion-at-PITR-window logic
- Encrypt backups with a separate key; rotation effectively expires old backups

Don't keep backups forever. "Just in case" is a privacy violation.

### 12. Treat third-party processors as your data plane.

Every SaaS you send user data to (Stripe, OpenAI, Resend, Datadog, PostHog, Sentry, Cloudflare) is a sub-processor in privacy terms. Audit:
- What data they receive
- What region they store in
- Their retention policy
- Their breach-notification SLA
- Whether you've signed a DPA

If your privacy policy doesn't list them, your privacy policy is wrong.

## Specific data classes that earn extra care

| Class | Notes |
|---|---|
| **Health (PHI)** | HIPAA in US; specific BAAs with processors; minimal logging |
| **Children's data** | COPPA in US; consent flows; no behavioral ads |
| **Biometrics** | BIPA (Illinois) is brutal; explicit written consent |
| **Location** | High-resolution location is sensitive even when the user is logged in; aggregate or coarsen |
| **Government IDs** | Encrypted-at-rest at the application layer; access audited; deletion on schedule |

## War story

A "remember the user's last 100 search queries" feature seemed innocuous. Two years later, a subpoena landed and the company had to produce two years of search history per user — including queries entered by mistake, by family members on shared devices, by minors. They hadn't documented retention, hadn't built deletion, hadn't asked whether they needed the history at all. The fix retroactively was painful: 30-day retention, app-level encryption, per-user delete on demand. Should have been: don't store more than 7 days unless the user opts in.

## Quick checklist

- [ ] Only fields the product *needs* are collected
- [ ] All transit encrypted (HTTPS, HSTS); internal hops too
- [ ] High-sensitivity fields encrypted at app level with a managed KMS
- [ ] Card data handled via tokenization (Stripe Elements / Checkout)
- [ ] Audit log for sensitive-data access
- [ ] Real deletion path (DB + indexes + caches + sub-processors), tested end-to-end
- [ ] Data export is structured and complete
- [ ] Logger redaction config blocks passwords, tokens, full PII
- [ ] Region-pinned for users with residency requirements
- [ ] DPA in place with sub-processors who touch user data
- [ ] Backup retention documented; deletion ages backups out predictably
- [ ] Privacy policy lists every sub-processor
