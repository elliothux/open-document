import type {
  PptxPoint,
  PptxGeometry,
  PptxQuery,
  PptxSelection,
} from "@open-document/wasm/pptx";
import type { PptxClient } from "./pptx.js";
import { pointerSelection } from "./presentation-selection.js";

export interface PresentationGesture {
  start: PptxPoint;
  kind: "text" | "transform" | "connector" | "guide";
  anchor: number;
  handle: number;
  token?: { revision: number; id: number };
}

interface GestureHost {
  state(): PptxQuery;
  geometry(): PptxGeometry | undefined;
  layoutId(): number;
  scale(): number;
  select(selection: PptxSelection): Promise<void>;
  focus(): void;
  changed(state: PptxQuery, relayout?: boolean): Promise<void>;
  enqueue(operation: () => Promise<void>): Promise<void>;
}

/** Share the editor queue and core candidates across text, objects and guides. */
export class PresentationGestures {
  private gesture: PresentationGesture | undefined;
  constructor(
    private readonly client: PptxClient,
    private readonly profile: Record<string, string>,
    private readonly host: GestureHost,
  ) {}
  get active(): boolean {
    return !!this.gesture;
  }
  reset(): void {
    this.gesture = undefined;
  }
  press(point: PptxPoint, text: boolean, extend: boolean): Promise<void> {
    return this.host.enqueue(async () => {
      const state = this.host.state(),
        scale = this.host.scale(),
        handle = presentationHandle(this.host.geometry(), state, point, scale);
      const hit = await this.client.execute({
        operation: "hitPptx",
        layoutId: this.host.layoutId(),
        ...point,
        tolerance: 4 / scale,
        text: text || state.selection.mode === "text",
      });
      if (
        !text &&
        !extend &&
        !handle &&
        state.guides.visible &&
        !state.guides.reason &&
        state.guides.items.length &&
        !state.selection.objects.includes(hit.object)
      ) {
        const next = await this.client.execute({
          operation: "beginGuidePptx",
          revision: state.revision,
          ...point,
          tolerance: 4 / scale,
        });
        if (next.candidateId !== null) {
          this.gesture = {
            start: point,
            kind: "guide",
            anchor: state.selection.anchor,
            handle: 0,
            token: { revision: next.revision, id: next.candidateId },
          };
          await this.host.changed(next);
          this.host.focus();
          return;
        }
      }
      const selection = pointerSelection(state, hit, handle, text, extend);
      await this.host.select(selection);
      this.gesture = {
        start: point,
        kind: presentationGestureKind(this.host.state(), handle),
        anchor: selection.anchor,
        handle,
      };
    });
  }
  move(point: PptxPoint, snap: boolean): Promise<void> {
    return this.host.enqueue(async () => {
      const gesture = this.gesture,
        state = this.host.state(),
        scale = this.host.scale();
      if (!gesture || (!state.selection.object && gesture.kind !== "guide"))
        return;
      if (gesture.kind === "text") {
        const hit = await this.client.execute({
          operation: "hitPptx",
          layoutId: this.host.layoutId(),
          ...point,
          tolerance: 4 / scale,
          text: true,
        });
        if (hit.object === state.selection.object)
          await this.host.select({
            ...state.selection,
            anchor: gesture.anchor,
            focus: hit.offset,
          });
      } else {
        const dx = point.x - gesture.start.x,
          dy = point.y - gesture.start.y;
        if (!gesture.token && Math.hypot(dx, dy) < 2 / scale) return;
        if (!gesture.token) {
          if (gesture.kind === "guide")
            throw new Error("Missing guide gesture identity");
          const next = await this.client.execute({
            operation: "beginPptx",
            revision: state.revision,
            kind: gesture.kind,
          });
          if (next.candidateId === null)
            throw new Error("Core did not begin drag");
          gesture.token = { revision: next.revision, id: next.candidateId };
          await this.host.changed(next);
        }
        await this.host.changed(
          await this.client.execute({
            operation: "dragPptx",
            revision: gesture.token.revision,
            candidateId: gesture.token.id,
            dx,
            dy,
            handle: gesture.handle,
            tolerance: snap ? 6 / scale : 0,
          }),
          true,
        );
      }
    });
  }
  async release(
    point: PptxPoint,
    cancel: boolean,
    snap: boolean,
  ): Promise<void> {
    if (!cancel) await this.move(point, snap);
    await this.host.enqueue(async () => {
      const gesture = this.gesture;
      this.gesture = undefined;
      if (gesture?.token)
        await this.host.changed(
          await this.client.execute({
            revision: gesture.token.revision,
            candidateId: gesture.token.id,
            ...(cancel
              ? { operation: "cancelPptx" as const }
              : { operation: "finishPptx" as const, profile: this.profile }),
          }),
          true,
        );
    });
  }
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
  move(point: PptxPoint, snap: boolean): Promise<void>;
  finish(point: PptxPoint, cancel: boolean, snap: boolean): Promise<void>;
  fail(error: Error): void;
}

/** Coalesce preview motion; pointer release always sends its final point. */
export class PresentationPointer {
  private pointer: number | undefined;
  private frame = 0;
  private pending: { point: PptxPoint; snap: boolean } | undefined;
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
          await host.finish(point, false, true);
        });
      },
      options,
    );
    canvas.addEventListener(
      "pointermove",
      (event) => {
        if (event.pointerId !== this.pointer) return;
        this.pending = { point: host.point(event), snap: !event.altKey };
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
          const snap = !event.altKey;
          this.append(() => host.finish(point, type !== "pointerup", snap));
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
      const pending = this.pending;
      this.pending = undefined;
      if (!pending) return;
      this.moving = true;
      this.append(async () => {
        try {
          await this.host.move(pending.point, pending.snap);
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
