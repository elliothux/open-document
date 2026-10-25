import type { FoundationClient } from "./foundation.js";
import type {
  DocxPictures,
  DocxShapes,
  DocxCharts,
  DocxSelectionGeometry,
} from "@open-document/wasm/foundation";
import type { DocxPointerHost } from "./document-pointer.js";
import {
  PointerSelection,
  clampPointerPoint,
  scrollPointerViewport,
  type PointerPoint,
} from "./pointer-selection.js";

/** Selected floating frames move; four corners resize in the same core gesture. */
export class DocxDrawingGesture {
  private image:
    | DocxPictures["images"][number]
    | DocxShapes["items"][number]
    | DocxCharts["items"][number]
    | undefined;
  private revision = -1;
  private readonly buttons: HTMLButtonElement[] = [];
  private readonly pointers: PointerSelection[] = [];
  private origin: PointerPoint = { x: 0, y: 0 };
  private point = this.origin;
  private scale = 1;
  private ending = false;
  private pageTime = 0;
  constructor(
    private readonly canvas: HTMLCanvasElement,
    viewport: HTMLElement,
    private readonly client: FoundationClient,
    signal: AbortSignal,
    private readonly host: DocxPointerHost,
  ) {
    for (const [i, corner] of [
      "top left",
      "top right",
      "bottom right",
      "bottom left",
      "move",
    ].entries()) {
      const button = document.createElement("button");
      button.type = "button";
      button.hidden = true;
      button.setAttribute(
        "aria-label",
        i === 4 ? "Move picture" : `Resize picture ${corner}`,
      );
      button.setAttribute(
        "aria-keyshortcuts",
        "ArrowLeft ArrowRight ArrowUp ArrowDown Escape",
      );
      Object.assign(button.style, {
        position: "absolute",
        width: "12px",
        height: "12px",
        padding: "0",
        border: i === 4 ? "none" : "2px solid white",
        background: i === 4 ? "transparent" : "#174ca0",
        cursor: i === 4 ? "move" : i % 2 ? "nesw-resize" : "nwse-resize",
        transform: i === 4 ? "none" : "translate(-50%, -50%)",
        zIndex: i === 4 ? "1" : "2",
      });
      viewport.append(button);
      this.buttons.push(button);
      const handle = (i === 4 ? 0 : i + 1) as 0 | 1 | 2 | 3 | 4;
      const pointer = new PointerSelection(
        button,
        viewport,
        signal,
        async (point, initial, _extend, elapsed) => {
          this.point = point;
          if (initial) {
            this.origin = handle === 0 ? this.local(point) : point;
            this.scale = host.current().scale;
            this.pageTime = performance.now();
            if (handle === 0) host.input();
            const drawing = this.image?.id;
            if (drawing === undefined)
              throw new Error("Select a drawing before starting a gesture");
            return host.gesture(() => ({ action: "begin", drawing, handle }));
          }
          return host.gesture(() => {
            if (handle === 0 && elapsed) {
              const current = host.current();
              const direction = scrollPointerViewport(
                viewport,
                point,
                elapsed,
                this.pageTime,
              );
              const next = current.page + direction;
              if (
                direction &&
                next >= 0 &&
                next < current.layout.regions.length
              ) {
                host.paint(next);
                viewport.scrollTop =
                  direction < 0
                    ? viewport.scrollHeight - viewport.clientHeight
                    : 0;
                this.pageTime = performance.now();
              }
            }
            return {
              action: "update",
              id: this.identity(),
              ...this.delta(point, handle),
            };
          });
        },
        () =>
          host.available() &&
          host.ink().options.tool === "select" &&
          !this.active &&
          !!this.image &&
          this.revision === host.current().state.revision,
        (cancelled) => {
          this.ending = true;
          // Output and toolbar updates can reflow the canvas before the queued commit runs.
          const delta = this.delta(this.point, handle);
          return host
            .gesture(() =>
              cancelled
                ? { action: "cancel", id: this.identity() }
                : {
                    action: "commit",
                    id: this.identity(),
                    ...delta,
                  },
            )
            .finally(() => {
              this.ending = false;
              void host.settle().catch(() => {});
            });
        },
        handle === 0,
      );
      this.pointers.push(pointer);
      button.addEventListener(
        "keydown",
        (event) => {
          if (
            !["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(
              event.key,
            ) ||
            !host.available() ||
            this.active ||
            !this.image ||
            this.revision !== host.current().state.revision
          )
            return;
          event.preventDefault();
          const drawing = this.image.id,
            step = event.shiftKey ? 10 : 1;
          const dx =
            event.key === "ArrowLeft"
              ? -step
              : event.key === "ArrowRight"
                ? step
                : 0;
          const dy =
            event.key === "ArrowUp"
              ? -step
              : event.key === "ArrowDown"
                ? step
                : 0;
          this.ending = true;
          void host
            .gesture(() => ({ action: "begin", drawing, handle }))
            .catch(() => {});
          void host
            .gesture(() => ({
              action: "commit",
              id: this.identity(),
              dx,
              dy,
            }))
            .finally(() => {
              this.ending = false;
              void host.settle().catch(() => {});
            })
            .catch(() => {});
        },
        { signal },
      );
    }
    window.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && this.pointers.some((p) => p.active)) {
          event.preventDefault();
          this.pointers.forEach((p) => p.finish(true));
        }
      },
      { signal },
    );
    signal.addEventListener(
      "abort",
      () => {
        this.reset();
        this.buttons.forEach((b) => b.remove());
      },
      { once: true },
    );
  }
  get active() {
    return this.ending || this.pointers.some((p) => p.active);
  }
  flush() {
    this.pointers.forEach((p) => p.flush());
  }
  finish() {
    this.pointers.forEach((p) => p.finish());
  }
  reset() {
    this.ending = false;
    this.pointers.forEach((p) => p.cancel());
    this.buttons.forEach((b) => (b.hidden = true));
  }
  private identity(): number {
    const id = this.host.current().state.drawingGestureId;
    if (id === null) throw new Error("Drawing gesture is no longer active");
    return id;
  }
  private local(point: PointerPoint): PointerPoint {
    const current = this.host.current();
    const frame = current.layout.regions[current.page];
    if (!frame) throw new Error("Unknown picture movement page");
    return clampPointerPoint(
      point,
      this.canvas.getBoundingClientRect(),
      current.scale,
      frame,
    );
  }
  private delta(point: PointerPoint, handle: number) {
    const local = handle === 0 ? this.local(point) : point;
    const scale = handle === 0 ? 1 : this.scale;
    return {
      ...(handle === 0 ? { page: this.host.current().page } : {}),
      dx: Math.max(-14400, Math.min(14400, (local.x - this.origin.x) / scale)),
      dy: Math.max(-14400, Math.min(14400, (local.y - this.origin.y) / scale)),
    };
  }
  async refresh(geometry: DocxSelectionGeometry | undefined): Promise<void> {
    const current = this.host.current(),
      selection = current.state.selection;
    if (current.state.drawingGestureId === null && !this.ending) {
      this.image = undefined;
      if (
        selection &&
        selection.anchor.paragraph === selection.focus.paragraph &&
        Math.abs(selection.anchor.offset - selection.focus.offset) === 1 &&
        this.host.available()
      ) {
        const catalog = await this.client.pictures(current.state.revision);
        this.host.assertOpen();
        this.revision = catalog.revision;
        this.image = catalog.images.find((image) => image.selected);
        if (!this.image) {
          const shapes = await this.client.shapes(current.state.revision);
          this.host.assertOpen();
          this.revision = shapes.revision;
          this.image = shapes.items.find((shape) => shape.selected);
        }
        if (!this.image) {
          const charts = await this.client.charts(current.state.revision);
          this.host.assertOpen();
          this.revision = charts.revision;
          this.image = charts.items.find((chart) => chart.selected);
        }
      }
    }
    const rect =
      this.image && geometry?.rects.find((r) => r.page === current.page);
    for (const [i, button] of this.buttons.entries()) {
      const kind =
        this.image && "preset" in this.image
          ? "shape"
          : this.image && "settings" in this.image
            ? "chart"
            : "picture";
      button.setAttribute(
        "aria-label",
        i === 4
          ? `Move ${kind}`
          : `Resize ${kind} ${["top left", "top right", "bottom right", "bottom left"][i]}`,
      );
      button.hidden =
        !rect ||
        this.host.ink().options.tool !== "select" ||
        !this.host.available() ||
        (i === 4
          ? !this.image?.anchor || !!this.image.positionReason
          : !!this.image &&
            ("sizeReason" in this.image
              ? !!this.image.sizeReason
              : !!this.image.reason));
      if (rect) {
        button.style.left = `${(rect.x + (i === 1 || i === 2 ? rect.width : 0)) * current.scale}px`;
        button.style.top = `${(rect.y + (i === 2 || i === 3 ? rect.height : 0)) * current.scale}px`;
        if (i === 4) {
          button.style.width = `${rect.width * current.scale}px`;
          button.style.height = `${rect.height * current.scale}px`;
        }
      }
    }
  }
}
