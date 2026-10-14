export interface PointerPoint {
  readonly x: number;
  readonly y: number;
}

/** Captures a gesture and coalesces unsent moves without buffering document state. */
export class PointerSelection {
  private pointerId: number | undefined;
  private point: PointerPoint | undefined;
  private dirty = false;
  private moved = false;
  private inFlight = 0;
  private frame: number | undefined;
  private time = 0;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly viewport: HTMLElement,
    signal: AbortSignal,
    private readonly apply: (
      point: PointerPoint,
      initial: boolean,
      extend: boolean,
      elapsed: number,
    ) => Promise<void>,
    private readonly enabled: () => boolean,
    private readonly settle: () => Promise<void>,
  ) {
    const options = { signal };
    canvas.style.touchAction = "none";
    canvas.addEventListener("pointerdown", this.down, options);
    canvas.addEventListener("pointermove", this.move, options);
    canvas.addEventListener("pointerup", this.up, options);
    const end = (event: PointerEvent) => {
      if (event.pointerId === this.pointerId) this.finish();
    };
    canvas.addEventListener("pointercancel", end, options);
    canvas.addEventListener("lostpointercapture", end, options);
    window.addEventListener("blur", () => this.finish(), options);
    signal.addEventListener("abort", () => this.cancel(), { once: true });
  }

  get active(): boolean {
    return this.pointerId !== undefined;
  }

  private sample(event: PointerEvent): void {
    if (event.clientX === this.point?.x && event.clientY === this.point.y)
      return;
    this.point = { x: event.clientX, y: event.clientY };
    this.dirty = true;
  }

  private readonly down = (event: PointerEvent): void => {
    if (event.button !== 0 || !event.isPrimary || !this.enabled()) return;
    event.preventDefault();
    this.finish();
    this.pointerId = event.pointerId;
    this.sample(event);
    this.canvas.setPointerCapture(event.pointerId);
    this.time = performance.now();
    this.send(true, event.shiftKey, 0);
    this.schedule();
  };

  private readonly move = (event: PointerEvent): void => {
    if (event.pointerId !== this.pointerId) return;
    event.preventDefault();
    if ((event.buttons & 1) === 0) {
      this.finish();
      return;
    }
    this.sample(event);
    if (this.dirty) this.moved = true;
  };

  private readonly up = (event: PointerEvent): void => {
    if (event.pointerId !== this.pointerId) return;
    event.preventDefault();
    this.sample(event);
    this.finish();
  };

  private send(initial: boolean, extend: boolean, elapsed: number): void {
    if (!this.point) return;
    this.dirty = false;
    this.inFlight++;
    void this.apply(this.point, initial, extend, elapsed)
      .catch(() => {})
      .finally(() => {
        this.inFlight--;
      });
  }

  private schedule(): void {
    this.frame = requestAnimationFrame((now) => {
      this.frame = undefined;
      if (!this.active) return;
      if (this.inFlight === 0) {
        const rect = this.viewport.getBoundingClientRect();
        const point = this.point;
        if (
          this.dirty ||
          (this.moved &&
            point &&
            (point.x < rect.left + 32 ||
              point.x > rect.left + this.viewport.clientWidth - 32 ||
              point.y < rect.top + 32 ||
              point.y > rect.top + this.viewport.clientHeight - 32))
        )
          this.send(false, true, Math.min(50, now - this.time));
        this.time = now;
      }
      if (this.active) this.schedule();
    });
  }

  /** Includes the latest received move in the editor's next barrier. */
  flush(): void {
    if (this.dirty) this.send(false, true, 0);
  }

  finish(): void {
    const active = this.active;
    this.flush();
    this.cancel();
    if (active) void this.settle().catch(() => {});
  }

  cancel(): void {
    const id = this.pointerId;
    this.pointerId = undefined;
    this.point = undefined;
    this.dirty = false;
    this.moved = false;
    if (this.frame !== undefined) cancelAnimationFrame(this.frame);
    this.frame = undefined;
    if (id !== undefined && this.canvas.hasPointerCapture(id))
      this.canvas.releasePointerCapture(id);
  }
}

export function revealInput(
  input: HTMLTextAreaElement,
  viewport: HTMLElement,
): void {
  input.scrollIntoView({ block: "nearest", inline: "nearest" });
  const target = input.getBoundingClientRect();
  const view = viewport;
  const box = view.getBoundingClientRect();
  const top = box.top + view.clientTop;
  const left = box.left + view.clientLeft;
  // Native nearest scrolling rounds fractional caret coordinates to CSS pixels.
  if (target.height <= view.clientHeight) {
    if (target.top < top) view.scrollTop -= Math.ceil(top - target.top);
    else if (target.bottom > top + view.clientHeight)
      view.scrollTop += Math.ceil(target.bottom - top - view.clientHeight);
  }
  if (target.width <= view.clientWidth) {
    if (target.left < left) view.scrollLeft -= Math.ceil(left - target.left);
    else if (target.right > left + view.clientWidth)
      view.scrollLeft += Math.ceil(target.right - left - view.clientWidth);
  }
}
