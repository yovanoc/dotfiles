---
name: file-uploads
description: Use when the user accepts file uploads, generates presigned URLs, proxies files to S3/R2/Blob storage, processes images/videos, or builds an "attach a file" feature. Catches server-proxied uploads (slow + memory-eating), unbounded sizes, MIME spoofing, image-resize abuse, and stored XSS via uploaded HTML/SVG.
---

# File Uploads

> If the user can pick a file, an attacker can pick anything. The defaults assume cooperation; the safe path assumes hostility.

## When to use
- Building "upload an avatar / attachment / document / video"
- Generating presigned URLs (S3, R2, GCS, Vercel Blob, UploadThing)
- Server-side image processing (resize, convert, OCR)
- Receiving files from a webhook or third-party

## When to skip
- Pure user-typed content (text, JSON) — that's `input-validation`

## The default architecture: direct-to-storage with presigned URLs

```
Browser ───presigned PUT───▶ S3/R2/Blob
   │                              │
   │      ───metadata POST──▶  Your server (records the upload)
```

Don't proxy file bytes through your serverless function. You'll OOM, time out, or pay for egress you didn't need to.

## The rules

### 1. Direct upload to storage. Server only signs the URL.

```ts
// app/api/uploads/sign/route.ts
import { z } from 'zod'

const Body = z.object({
  contentType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  size: z.number().int().min(1).max(5 * 1024 * 1024), // 5MB cap
})

export async function POST(req: Request) {
  const session = await getSession()
  if (!session) return new Response('Unauthorized', { status: 401 })

  const { contentType, size } = Body.parse(await req.json())

  const key = `users/${session.userId}/${crypto.randomUUID()}`
  const url = await getSignedUploadUrl({
    key,
    contentType,
    expiresIn: 60, // short-lived
    contentLengthRange: [1, 5 * 1024 * 1024], // bucket-enforced
  })

  return Response.json({ url, key })
}
```

The browser then `PUT`s the file directly to `url`. Your server never sees the bytes — fast, cheap, scales.

### 2. Cap size. At the bucket, not just at the form.

The form's `<input maxlength>` is a lie. The signed URL's `contentLengthRange` is enforced by the storage provider. **That's** the real limit.

For S3-compatible: `Content-Length` constraint in the policy. For Vercel Blob: `maximumSizeInBytes` in the client token. For R2 (presigned): include `content-length-range` in the policy.

### 3. Validate `Content-Type` server-side. Don't trust the upload's claim.

The browser sends whatever MIME the user picked. To know what the file *actually* is, sniff the bytes after upload (or before, if you must proxy):

```ts
import { fileTypeFromBuffer } from 'file-type'
const detected = await fileTypeFromBuffer(buffer.subarray(0, 4096))
if (!detected || !ALLOWED_MIMES.has(detected.mime)) {
  await deleteObject(key)
  return new Response('Bad file', { status: 400 })
}
```

Rejecting on extension + claimed MIME alone is bypassable trivially (rename `.exe` → `.jpg`).

### 4. Never serve user uploads from your primary domain.

Stored uploads served from `yourapp.com` execute in your origin. A user uploads `evil.svg` containing `<script>` and visits the URL — XSS in your auth context.

Serve from a separate domain (`uploads.example-cdn.com`, `*.r2.cloudflarestorage.com`, a signed URL). Set `Content-Disposition: attachment` for any non-image type. Set `Content-Security-Policy: sandbox` on the served bucket.

### 5. SVG is an executable format. Treat it like one.

SVGs can contain `<script>` and event handlers. Either:
- **Don't accept SVG.** Easiest.
- Sanitize server-side with DOMPurify (configured for SVG) before accepting.
- Serve with `Content-Disposition: attachment` and `Content-Security-Policy` so it never renders in-page.
- Convert to PNG server-side and store the rasterized version.

### 6. Image-resize abuse. Cap dimensions, not just file size.

A 1MB PNG can be 50,000 × 50,000 pixels — decoding it allocates ~10GB. **Decompression bombs** crash workers and trigger OOM.

```ts
import sharp from 'sharp'
const meta = await sharp(buffer, { failOnError: true }).metadata()
if ((meta.width ?? 0) > 8000 || (meta.height ?? 0) > 8000 || (meta.pages ?? 1) > 1) {
  throw new Error('image too large')
}
const out = await sharp(buffer, { limitInputPixels: 50_000_000 }).resize(...).toBuffer()
```

`limitInputPixels` is a hard ceiling. Set it to a sane max (e.g., 50MP).

### 7. Strip EXIF (location data) from images.

Photos from phones embed GPS coordinates. Sharing a user's profile photo with EXIF intact leaks where they took it.

```ts
sharp(buffer).rotate().toBuffer() // .rotate() applies EXIF orientation, then strips
// Or explicitly:
sharp(buffer).keepMetadata(false).toBuffer()
```

### 8. Scope the key by user/tenant. Authorize on download.

```ts
// BAD — user A guesses user B's key, downloads
const key = `uploads/${randomId}`

// GOOD — keyed by owner; download endpoint checks ownership
const key = `users/${userId}/${randomId}`
```

For private files, generate **short-lived signed download URLs** when serving — don't make objects public.

### 9. Virus / malware scan for files that go to other users.

If user A uploads → user B downloads, A can plant malware via a shared "attachment" feature. Scan async after upload (ClamAV, Cloudmark, a paid API). Mark the file as "scanning" → "clean" / "infected" before exposing the download URL.

For internal-only files (the user's own profile pic), the risk is lower; a scan is still nice to have.

### 10. Filename: don't trust it. Don't preserve it server-side.

```ts
// BAD — user-supplied path can include `../`, NULL bytes, control chars
const path = `/uploads/${file.name}`
fs.writeFileSync(path, buffer) // path traversal

// GOOD — use a generated key; store the original name as a separate metadata field
const key = `${crypto.randomUUID()}` // server-generated
await db.upload.create({ data: { key, originalName: sanitize(file.name), ownerId } })
```

When serving, set `Content-Disposition: attachment; filename="..."` with a sanitized version.

### 11. Cleanup orphans.

If the client gets a signed URL, uploads the file, but then crashes before posting the metadata: you have an object with no DB record. Periodically (daily) reconcile bucket vs DB and delete unreferenced objects older than N hours.

### 12. Quotas per user.

Free-tier users with unlimited storage = a Tor user uploading 1TB of warez via your free product. Track per-user storage usage; reject when over quota; clean up when the user is deleted.

## Provider notes (2026)

| Provider | Direct upload? | Notes |
|---|---|---|
| AWS S3 | ✅ presigned POST/PUT | Use POST with policy for size constraints |
| Cloudflare R2 | ✅ presigned (S3-compatible API) | Cheaper egress, same patterns |
| Vercel Blob | ✅ client tokens | Token-scoped, expirable |
| UploadThing | ✅ purpose-built | Validation layer on top |
| Supabase Storage | ✅ direct upload via SDK + RLS | RLS enforces ownership |

Don't proxy through your function unless you have a reason (e.g., must inspect content before accepting).

## War story

An indie SaaS allowed any image upload via a server-proxied endpoint. No size cap on dimensions. A user uploaded a 60,000 × 60,000 PNG (40KB compressed via aggressive RLE). Sharp's decoder allocated ~14GB. Every Vercel function invocation that processed it OOMed. Three functions crashed simultaneously, restart loop, full availability incident. Fix: `limitInputPixels`, dimension check before decode, and direct-to-storage instead of proxy. 20 minutes of work. 4 hours of outage.

## Quick checklist

- [ ] Direct upload to storage; server only signs URLs
- [ ] Size cap enforced at the bucket (`contentLengthRange`)
- [ ] Server-side MIME sniffing after upload, not trusting claimed MIME
- [ ] Uploads served from a separate domain (or signed, attachment-only)
- [ ] SVG either rejected, sanitized, or rasterized
- [ ] Image dimensions capped via `limitInputPixels`
- [ ] EXIF stripped from images
- [ ] Object keys scoped by owner; download URLs short-lived
- [ ] Virus scan for files that other users will download
- [ ] Filename is server-generated; original stored as metadata
- [ ] Orphan cleanup job
- [ ] Per-user storage quotas
