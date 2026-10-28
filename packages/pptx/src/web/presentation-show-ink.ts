import type { PptxShowInkChange, PptxShowState } from "../core/pptx.js";

export interface PresentationInkLabels {
  pen: string;
  penColor: string;
  clearInk: string;
}
interface InkFrame {
  id: number;
  slide: string;
  width: number;
  height: number;
}
interface InkGesture {
  pointer: number;
  frame: InkFrame;
  color: string;
  points: { x: number; y: number }[];
  started: boolean;
  finish?: "end";
}

/** Batches platform pointer samples; the core owns strokes and their R0 drawing. */
export class PresentationShowInk {
  private gesture: InkGesture | undefined;
  private frameRequest = 0;
  private pending: Promise<void> | undefined;
  private suppressClick = false;
  private readonly pen: HTMLButtonElement;
  private readonly clear: HTMLButtonElement;
  enabled = false;
  constructor(
    private readonly canvas: HTMLCanvasElement,
    controls: HTMLElement,
    dialog: HTMLElement,
    signal: AbortSignal,
    labels: PresentationInkLabels,
    private readonly frame: () => InkFrame | undefined,
    private readonly send: (
      change: PptxShowInkChange,
      layoutId?: number,
    ) => Promise<void>,
    private readonly report: (error: unknown) => void,
  ) {
    const pen = document.createElement("button"),
      clear = document.createElement("button"),
      color = document.createElement("input");
    this.pen = pen;
    this.clear = clear;
    pen.type = clear.type = "button";
    pen.textContent = labels.pen;
    pen.setAttribute("aria-pressed", "false");
    clear.textContent = labels.clearInk;
    clear.disabled = true;
    color.type = "color";
    color.value = "#ff0000";
    color.setAttribute("aria-label", labels.penColor);
    controls.append(pen, color, clear);
    const options = { signal };
    pen.addEventListener(
      "click",
      () => {
        this.enable(!this.enabled);
        if (!this.enabled) void this.cancel().catch(report);
      },
      options,
    );
    clear.addEventListener(
      "click",
      () => {
        this.reset();
        void (this.pending ?? Promise.resolve())
          .then(() => this.send({ action: "clear" }))
          .catch(report);
      },
      options,
    );
    dialog.addEventListener(
      "keydown",
      (event) => {
        if (event.key !== "Escape" || !this.enabled) return;
        event.preventDefault();
        this.suppressClick = true;
        event.stopImmediatePropagation();
        this.enable(false);
        void this.cancel().catch(report);
      },
      { signal, capture: true },
    );
    canvas.addEventListener(
      "pointerdown",
      (event) => {
        if (
          !this.enabled ||
          event.button !== 0 ||
          !event.isPrimary ||
          this.gesture ||
          this.pending
        )
          return;
        const frame = this.frame();
        if (!frame) return;
        event.preventDefault();
        this.gesture = {
          pointer: event.pointerId,
          frame,
          color: color.value.slice(1),
          points: [],
          started: false,
        };
        canvas.setPointerCapture(event.pointerId);
        this.sample(event);
      },
      options,
    );
    canvas.addEventListener(
      "pointermove",
      (event) => this.sample(event),
      options,
    );
    canvas.addEventListener(
      "pointerup",
      (event) => {
        if (this.gesture?.pointer !== event.pointerId) return;
        this.sample(event);
        this.gesture.finish = "end";
        this.schedule();
      },
      options,
    );
    for (const type of ["pointercancel", "lostpointercapture"])
      canvas.addEventListener(
        type,
        (event) => {
          if (
            event instanceof PointerEvent &&
            this.gesture?.pointer === event.pointerId &&
            !this.gesture.finish
          )
            void this.cancel().catch(report);
        },
        options,
      );
    signal.addEventListener("abort", () => this.reset(), { once: true });
  }
  private enable(value: boolean): void {
    this.enabled = value;
    this.pen.setAttribute("aria-pressed", String(value));
    this.canvas.style.cursor = value ? "crosshair" : "";
    this.canvas.style.touchAction = value ? "none" : "";
  }
  update(state: PptxShowState): void {
    this.clear.disabled = state.ink.points === 0;
    if (this.gesture && this.gesture.frame.slide !== state.slide) this.reset();
  }
  consumeClick(): boolean {
    const suppress = this.enabled || this.suppressClick;
    this.suppressClick = false;
    return suppress;
  }
  reset(): void {
    const gesture = this.gesture;
    this.gesture = undefined;
    cancelAnimationFrame(this.frameRequest);
    this.frameRequest = 0;
    if (gesture && this.canvas.hasPointerCapture(gesture.pointer))
      this.canvas.releasePointerCapture(gesture.pointer);
  }
  async settle(): Promise<void> {
    await this.pending;
    cancelAnimationFrame(this.frameRequest);
    this.frameRequest = 0;
    while (this.gesture?.finish) await this.flush();
    if (this.gesture) await this.cancel();
  }
  private cancel(): Promise<void> {
    this.reset();
    return (this.pending ?? Promise.resolve()).then(() =>
      this.send({ action: "cancel" }),
    );
  }
  private sample(event: PointerEvent): void {
    const gesture = this.gesture;
    if (!gesture || gesture.pointer !== event.pointerId || gesture.finish)
      return;
    const rect = this.canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const coalesced = event.getCoalescedEvents(),
      samples = coalesced.length ? coalesced : [event];
    if (gesture.points.length + samples.length > 4096) {
      void this.cancel()
        .then(() => {
          throw new Error("Ink pointer buffer exceeds budget");
        })
        .catch(this.report);
      return;
    }
    for (const point of samples)
      gesture.points.push({
        x: Math.min(
          gesture.frame.width,
          Math.max(
            0,
            ((point.clientX - rect.left) * gesture.frame.width) / rect.width,
          ),
        ),
        y: Math.min(
          gesture.frame.height,
          Math.max(
            0,
            ((point.clientY - rect.top) * gesture.frame.height) / rect.height,
          ),
        ),
      });
    this.schedule();
  }
  private schedule(): void {
    if (this.frameRequest || this.pending || !this.gesture) return;
    this.frameRequest = requestAnimationFrame(() => {
      this.frameRequest = 0;
      this.pending = this.flush()
        .catch(async (error) => {
          this.reset();
          try {
            await this.send({ action: "cancel" });
          } catch {
            /* The scene may already have ended. */
          }
          this.report(error);
        })
        .finally(() => {
          this.pending = undefined;
          if (
            this.gesture &&
            (this.gesture.points.length || this.gesture.finish)
          )
            this.schedule();
        });
    });
  }
  private async flush(): Promise<void> {
    const gesture = this.gesture;
    if (!gesture) return;
    const points = gesture.points.splice(0, 64);
    const change: PptxShowInkChange = !gesture.started
      ? { action: "begin", color: gesture.color, width: 2.25, points }
      : {
          action: gesture.finish && !gesture.points.length ? "end" : "append",
          points,
        };
    const frame = this.frame();
    if (!frame || frame.slide !== gesture.frame.slide) {
      this.reset();
      return;
    }
    await this.send(change, gesture.started ? frame.id : gesture.frame.id);
    if (this.gesture !== gesture) return;
    gesture.started = true;
    if (change.action === "end") this.reset();
  }
}
