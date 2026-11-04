export type CacheProvenance = { hit: boolean; ageMs: number; ttlMs: number };
type Snapshot = { capturedAt: number | null; status: string; cache?: CacheProvenance; windows?: { resetsAt: number | null }[] };
export type CacheOptions<T extends Snapshot> = { cache: QuotaCache<T>; refresh?: boolean };

// One bounded in-memory entry per collector; never persist credentials or observations.
export class QuotaCache<T extends Snapshot> {
  private entry?: { key: string; value: T };
  readonly ttlMs = 60_000;
  private clock: () => number;
  constructor(clock: () => number = Date.now) { this.clock = clock; }

  read(key: string, refresh = false): (T & { cache: CacheProvenance }) | undefined {
    const entry = this.entry;
    if (!refresh && entry?.key === key && entry.value.capturedAt !== null && this.valid(entry.value)) {
      return { ...entry.value, cache: { hit: true, ageMs: this.clock() - entry.value.capturedAt, ttlMs: this.ttlMs } };
    }
    this.entry = undefined;
    return undefined;
  }

  write(key: string, value: T): T & { cache: CacheProvenance } {
    this.entry = this.valid(value) ? { key, value } : undefined;
    return { ...value, cache: { hit: false, ageMs: value.capturedAt === null ? 0 : Math.max(0, this.clock() - value.capturedAt), ttlMs: this.ttlMs } };
  }

  clear(): void { this.entry = undefined; }

  // Validate again after asynchronous auth/aggregation, immediately before publication.
  publish(value: T, invalid: T, now = this.clock()): T {
    if (!value.cache) return value;
    const cache = { ...value.cache, ageMs: value.capturedAt === null ? 0 : Math.max(0, now - value.capturedAt) };
    if (value.cache.hit && !this.valid(value, now)) {
      this.clear();
      return { ...invalid, capturedAt: value.capturedAt, cache };
    }
    return { ...value, cache };
  }

  private valid(value: T, now = this.clock()): boolean {
    return value.status === "fresh" && value.capturedAt !== null && Number.isFinite(value.capturedAt)
      && now >= value.capturedAt && now - value.capturedAt < this.ttlMs
      && !(value.windows ?? []).some(({ resetsAt }) => resetsAt !== null && resetsAt * 1000 <= now);
  }
}
