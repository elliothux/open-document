import type {
  PptxPoint,
  PptxGeometry,
  PptxQuery,
} from "@open-document/wasm/pptx";

export interface PresentationGesture {
  start: PptxPoint;
  kind: "text" | "transform" | "connector";
  anchor: number;
  handle: number;
  token?: { revision: number; id: number };
}

export function presentationHandle(
  geometry: PptxGeometry | undefined,
  state: PptxQuery,
  point: PptxPoint,
  scale: number,
): number {
  if (state.selection.mode !== "object") return 0;
  let handle = 0;
  for (const [index, position] of (geometry?.handles ?? []).entries())
    if (Math.hypot(point.x - position.x, point.y - position.y) <= 6 / scale)
      handle = index + 1;
  return handle;
}

export function presentationGestureKind(
  state: PptxQuery,
  handle: number,
): PresentationGesture["kind"] {
  if (state.selection.mode === "text") return "text";
  return handle &&
    state.selection.objects.length === 1 &&
    state.objects.find((o) => o.id === state.selection.object)?.connector
    ? "connector"
    : "transform";
}

export interface PresentationPointerHost {
  available(): boolean;
  point(event: MouseEvent): PptxPoint;
  press(point: PptxPoint, text: boolean, extend: boolean): Promise<void>;
  move(point: PptxPoint): Promise<void>;
  finish(point: PptxPoint, cancel: boolean): Promise<void>;
  fail(error: Error): void;
}

/** Coalesce preview motion; pointer release always sends its final point. */
export class PresentationPointer {
  private pointer: number | undefined;
  private frame = 0;
  private pending: PptxPoint | undefined;
  private tail: Promise<void> = Promise.resolve();
  private queued = 0;
  private moving = false;
  constructor(
    private readonly canvas: HTMLCanvasElement,
    signal: AbortSignal,
    private readonly host: PresentationPointerHost,
  ) {
    const options = { signal };
    canvas.addEventListener(
      "pointerdown",
      (event) => {
        if (event.button !== 0 || this.active || !host.available()) return;
        event.preventDefault();
        this.pointer = event.pointerId;
        canvas.setPointerCapture(event.pointerId);
        const point = host.point(event),
          extend = event.shiftKey;
        this.append(() => host.press(point, false, extend), true);
      },
      options,
    );
    canvas.addEventListener(
      "dblclick",
      (event) => {
        if (!host.available()) return;
        event.preventDefault();
        const point = host.point(event);
        this.append(async () => {
          await host.press(point, true, event.shiftKey);
          await host.finish(point, false);
        });
      },
      options,
    );
    canvas.addEventListener(
      "pointermove",
      (event) => {
        if (event.pointerId !== this.pointer) return;
        this.pending = host.point(event);
        this.schedule();
      },
      options,
    );
    for (const type of [
      "pointerup",
      "pointercancel",
      "lostpointercapture",
    ] as const)
      canvas.addEventListener(
        type,
        (event) => {
          if (event.pointerId !== this.pointer) return;
          if (
            type === "lostpointercapture" &&
            canvas.hasPointerCapture(event.pointerId)
          )
            return;
          this.reset();
          const point = host.point(event);
          this.append(() => host.finish(point, type !== "pointerup"));
        },
        options,
      );
  }
  get active(): boolean {
    return this.pointer !== undefined;
  }
  private append(operation: () => Promise<void>, recover = false): void {
    if (this.queued >= 64) {
      this.host.fail(new Error("Pointer queue exceeds budget"));
      return;
    }
    this.queued++;
    this.tail = (recover ? this.tail.catch(() => {}) : this.tail)
      .then(operation)
      .finally(() => {
        this.queued--;
      });
    void this.tail.catch((error) =>
      this.host.fail(error instanceof Error ? error : new Error(String(error))),
    );
  }
  private schedule(): void {
    if (this.frame || this.moving || !this.active || !this.pending) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      const point = this.pending;
      this.pending = undefined;
      if (!point) return;
      this.moving = true;
      this.append(async () => {
        try {
          await this.host.move(point);
        } finally {
          this.moving = false;
          this.schedule();
        }
      });
    });
  }
  reset(): void {
    const id = this.pointer;
    this.pointer = undefined;
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.pending = undefined;
    this.moving = false;
    if (id !== undefined && this.canvas.hasPointerCapture(id))
      this.canvas.releasePointerCapture(id);
  }
}
