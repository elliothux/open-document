/** Bounded serialization shared by document hosts; recovery barriers bypass admission. */
export class CommandQueue {
  private tail: Promise<void> = Promise.resolve();
  private count = 0;
  private nonBlockingCount = 0;
  private epoch = 0;

  constructor(
    private readonly limit: number,
    private readonly overflow: () => Error,
  ) {}

  get pending(): number {
    return this.count;
  }

  get blocking(): number {
    return this.count - this.nonBlockingCount;
  }

  get generation(): number {
    return this.epoch;
  }

  invalidate(): void {
    this.epoch++;
  }

  whenIdle(): Promise<void> {
    return this.tail;
  }

  enqueue<T>(
    operation: () => Promise<T>,
    started: () => void,
    settled: (result: PromiseSettledResult<void>) => void,
    nonBlocking = false,
  ): Promise<T> {
    if (this.count >= this.limit) return Promise.reject(this.overflow());
    this.count++;
    if (nonBlocking) this.nonBlockingCount++;
    const result = this.tail.then(operation);
    this.tail = result.then(
      () => {
        this.count--;
        if (nonBlocking) this.nonBlockingCount--;
        settled({ status: "fulfilled", value: undefined });
      },
      (reason: unknown) => {
        this.count--;
        if (nonBlocking) this.nonBlockingCount--;
        settled({ status: "rejected", reason });
      },
    );
    started();
    return result;
  }

  /** Serialize recovery after accepted work without consuming an input slot. */
  barrier<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.tail.then(operation);
    this.tail = result.then(
      () => {},
      () => {},
    );
    return result;
  }
}
