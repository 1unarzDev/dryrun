// Small per-isolate TTL cache. Holds only public responses.
export class TTLCache<V> {
  private store = new Map<string, { value: V; expiresAt: number }>();
  constructor(private maxEntries = 200) {}
  get(key: string, now: number): V | undefined {
    const e = this.store.get(key);
    if (!e) return undefined;
    if (now >= e.expiresAt) { this.store.delete(key); return undefined; }
    return e.value;
  }
  set(key: string, value: V, ttlMs: number, now: number): void {
    if (this.store.size >= this.maxEntries) this.store.delete(this.store.keys().next().value as string);
    this.store.set(key, { value, expiresAt: now + ttlMs });
  }
}
