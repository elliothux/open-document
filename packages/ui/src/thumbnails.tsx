import {
  memo,
  useCallback,
  useEffect,
  useMemo,
  useSyncExternalStore,
} from "react";

type LoadThumbnail = (
  key: string,
  revision: number,
  signal: AbortSignal,
) => Promise<Blob>;
type Entry = { url: string; bytes: number; version: number };

const entryLimit = 96;
const byteLimit = 16 * 1024 * 1024;

class ThumbnailCache {
  private readonly entries = new Map<string, Entry>();
  private readonly attempted = new Map<string, number>();
  private readonly failed = new Map<string, number>();
  private readonly visible = new Set<string>();
  private readonly elements = new Map<Element, string>();
  private readonly listeners = new Map<string, Set<() => void>>();
  private versions = new Map<string, number>();
  private order: string[] = [];
  private observer: IntersectionObserver | undefined;
  private running: AbortController | undefined;
  private idle: number | undefined;
  private timer: number | undefined;
  private revision = -1;
  private active = "";
  private readyAt = 0;
  private paused = false;
  private bytes = 0;

  constructor(private readonly load: LoadThumbnail) {}

  setPaused(paused: boolean) {
    this.paused = paused;
    if (paused) this.running?.abort();
    else this.schedule();
  }

  update(
    keys: string[],
    active: string,
    revision: number,
    version: (key: string) => number,
  ) {
    if (this.active !== active) {
      this.active = active;
      this.attempted.delete(active);
      this.failed.delete(active);
    }
    if (revision !== this.revision) {
      this.running?.abort();
      if (this.revision !== -1) this.readyAt = performance.now() + 160;
      this.revision = revision;
    }
    this.versions = new Map(keys.map((key) => [key, version(key)]));
    const pivot = Math.max(0, keys.indexOf(active));
    this.order = keys
      .map((key, index) => ({ key, distance: Math.abs(index - pivot) }))
      .sort((a, b) => a.distance - b.distance)
      .map(({ key }) => key);
    for (const key of this.entries.keys())
      if (!this.versions.has(key)) this.remove(key);
    for (const key of this.attempted.keys())
      if (!this.versions.has(key)) this.attempted.delete(key);
    for (const key of this.failed.keys())
      if (!this.versions.has(key)) this.failed.delete(key);
    this.schedule();
  }

  watch(element: Element, key: string): () => void {
    this.observer ??= new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          const key = this.elements.get(entry.target);
          if (key === undefined) continue;
          if (entry.isIntersecting) {
            if (!this.visible.has(key)) this.attempted.delete(key);
            this.visible.add(key);
            const cached = this.entries.get(key);
            if (cached) {
              this.entries.delete(key);
              this.entries.set(key, cached);
            }
          } else this.visible.delete(key);
        }
        this.schedule();
      },
      { root: element.closest("nav"), rootMargin: "160px 0px" },
    );
    this.elements.set(element, key);
    this.observer.observe(element);
    return () => {
      this.observer?.unobserve(element);
      this.elements.delete(element);
      this.visible.delete(key);
      if (!this.elements.size) {
        this.observer?.disconnect();
        this.observer = undefined;
      }
    };
  }

  get(key: string): string | undefined {
    return this.entries.get(key)?.url;
  }

  subscribe(key: string, listener: () => void): () => void {
    const set = this.listeners.get(key) ?? new Set();
    this.listeners.set(key, set);
    set.add(listener);
    return () => {
      set.delete(listener);
      if (!set.size) this.listeners.delete(key);
    };
  }

  reset() {
    this.running?.abort();
    if (this.idle !== undefined) cancelIdleCallback(this.idle);
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.idle = this.timer = undefined;
    this.order = [];
    this.versions.clear();
    this.attempted.clear();
    this.failed.clear();
    for (const key of this.entries.keys()) this.remove(key);
    this.revision = -1;
    this.readyAt = 0;
  }

  private remove(key: string) {
    const entry = this.entries.get(key);
    if (!entry) return;
    URL.revokeObjectURL(entry.url);
    this.entries.delete(key);
    this.bytes -= entry.bytes;
    this.notify(key);
  }

  private notify(key: string) {
    for (const listener of this.listeners.get(key) ?? []) listener();
  }

  private next(): string | undefined {
    if (this.paused) return undefined;
    const needs = (key: string) => {
      const version = this.versions.get(key);
      return (
        version !== undefined &&
        this.entries.get(key)?.version !== version &&
        this.attempted.get(key) !== version &&
        this.failed.get(key) !== version
      );
    };
    return (
      this.order.find((key) => this.visible.has(key) && needs(key)) ??
      this.order.find(
        (key) =>
          needs(key) &&
          (this.entries.has(key) ||
            (this.entries.size < entryLimit && this.bytes < byteLimit)),
      )
    );
  }

  private schedule() {
    if (
      this.running ||
      this.idle !== undefined ||
      this.timer !== undefined ||
      !this.next()
    )
      return;
    const delay = this.readyAt - performance.now();
    if (delay > 0) {
      this.timer = window.setTimeout(() => {
        this.timer = undefined;
        this.schedule();
      }, delay);
      return;
    }
    this.idle = requestIdleCallback(
      () => {
        this.idle = undefined;
        if (performance.now() < this.readyAt) {
          this.schedule();
          return;
        }
        const key = this.next();
        if (key !== undefined) void this.render(key);
      },
      { timeout: 250 },
    );
  }

  private async render(key: string) {
    const version = this.versions.get(key)!;
    const abort = new AbortController();
    this.running = abort;
    try {
      const blob = await this.load(key, this.revision, abort.signal);
      if (abort.signal.aborted || this.versions.get(key) !== version) return;
      if (blob.size > byteLimit)
        throw new Error("Thumbnail exceeds cache budget");
      const old = this.entries.get(key);
      if (old) {
        this.bytes -= old.bytes;
        this.entries.delete(key);
      }
      while (
        this.entries.size >= entryLimit ||
        this.bytes + blob.size > byteLimit
      ) {
        const oldest = this.entries.keys().next().value!;
        const offscreen = [...this.entries.keys()].find(
          (item) => !this.visible.has(item),
        );
        this.remove(offscreen ?? oldest);
      }
      this.entries.set(key, {
        url: URL.createObjectURL(blob),
        bytes: blob.size,
        version,
      });
      if (old) URL.revokeObjectURL(old.url);
      this.bytes += blob.size;
      this.attempted.set(key, version);
      this.notify(key);
    } catch {
      if (!abort.signal.aborted && this.versions.get(key) === version)
        this.failed.set(key, version);
    } finally {
      this.running = undefined;
      this.schedule();
    }
  }
}

export function useThumbnails(
  load: LoadThumbnail,
  keys: string[],
  active: string,
  revision: number,
  options: { paused?: boolean; version?: (key: string) => number } = {},
): ThumbnailCache {
  const cache = useMemo(() => new ThumbnailCache(load), [load]);
  const { paused = false, version } = options;
  const identity = keys.join("\0");
  useEffect(() => () => cache.reset(), [cache]);
  useEffect(() => cache.setPaused(paused), [cache, paused]);
  useEffect(() => {
    cache.update(
      identity ? identity.split("\0") : [],
      active,
      revision,
      version ?? (() => revision),
    );
  }, [cache, identity, active, revision, version]);
  return cache;
}

export const CachedThumbnail = memo(function CachedThumbnail({
  cache,
  id,
  className,
  aspectRatio,
}: {
  cache: ThumbnailCache;
  id: string;
  className: string;
  aspectRatio?: number;
}) {
  const watch = useCallback(
    (element: HTMLSpanElement | null) =>
      element ? cache.watch(element, id) : undefined,
    [cache, id],
  );
  const subscribe = useCallback(
    (listener: () => void) => cache.subscribe(id, listener),
    [cache, id],
  );
  const url = useSyncExternalStore(subscribe, () => cache.get(id));
  return (
    <span
      ref={watch}
      className={className}
      style={aspectRatio ? { aspectRatio } : undefined}
      aria-hidden="true"
    >
      {url && <img src={url} alt="" draggable={false} decoding="async" />}
    </span>
  );
});
