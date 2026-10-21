import type { XlsxClient, XlsxFillPreview, XlsxFillTarget } from "./xlsx.js";
import type {
  XlsxQuery,
  XlsxViewport,
  XlsxSelectionGeometry,
} from "@open-document/wasm/xlsx";
import type { CanvasSurface } from "./canvas-surface.js";
import { paintGridSelection } from "./spreadsheet-input.js";
import { SpreadsheetNotes } from "./spreadsheet-notes.js";
import { SpreadsheetPicturePointer } from "./spreadsheet-picture-pointer.js";

export interface PointerHost {
  current(): {
    query: XlsxQuery;
    layout: XlsxViewport | undefined;
    scale: number;
    disabled: boolean;
    profile: Record<string, string>;
  };
  run<T>(action: () => Promise<T>): Promise<T>;
  prepare(): Promise<void>;
  assign(query: XlsxQuery): void;
  render(): Promise<void>;
  focus(): void;
  edit(): void;
  changed(): void;
  report(error: unknown): void;
}
interface Source {
  revision: number;
  sheet: string;
  source: string;
}
interface Drag {
  id: number;
  origin: { x: number; y: number };
  ready: Promise<void>;
  source?: Source;
  point?: { x: number; y: number };
  pending?: { x: number; y: number };
  busy?: Promise<void>;
  released: boolean;
  ctrl: boolean;
}

/** Pointer intents and overlays; core geometry and the normal command queue own the result. */
export class SpreadsheetPointer {
  get dragging(): boolean {
    return this.drag !== undefined || this.pictures.active;
  }
  private readonly handle = document.createElement("button");
  private geometry: XlsxSelectionGeometry | undefined;
  private drag: Drag | undefined;
  private frame = 0;
  private preparing = false;
  private readonly notes: SpreadsheetNotes;
  private readonly pictures: SpreadsheetPicturePointer;
  constructor(
    private readonly surface: CanvasSurface,
    holder: HTMLElement,
    private readonly viewport: HTMLElement,
    input: HTMLTextAreaElement,
    private readonly client: XlsxClient,
    private readonly signal: AbortSignal,
    private readonly host: PointerHost,
  ) {
    this.pictures = new SpreadsheetPicturePointer(
      surface,
      holder,
      viewport,
      client,
      signal,
      host,
    );
    this.notes = new SpreadsheetNotes(
      surface.canvas,
      holder,
      viewport,
      input,
      signal,
      () => host.current(),
    );
    this.handle.type = "button";
    this.handle.hidden = true;
    this.handle.setAttribute("aria-label", "Fill handle");
    this.handle.setAttribute(
      "aria-keyshortcuts",
      "ArrowUp ArrowDown ArrowLeft ArrowRight Enter Space",
    );
    this.handle.title =
      "Drag outward to fill or inward to clear contents; double-click or press Enter/Space to fill along adjacent data; Ctrl toggles copy/series; arrow keys extend one row or column";
    Object.assign(this.handle.style, {
      position: "absolute",
      width: "10px",
      height: "10px",
      padding: "0",
      border: "1px solid white",
      borderRadius: "0",
      background: "#2563eb",
      cursor: "crosshair",
      touchAction: "none",
      zIndex: "3",
    });
    holder.append(this.handle);
    const options = { signal };
    surface.canvas.addEventListener(
      "pointerdown",
      (event) => {
        if (event.button !== 0 || this.host.current().disabled) return;
        event.preventDefault();
        this.cancel();
        this.accept(
          this.host.run(async () => {
            await host.prepare();
            const now = host.current();
            if (!now.layout) return;
            const rect = surface.canvas.getBoundingClientRect();
            const address = await client.hit(
              now.layout.id,
              (event.clientX - rect.left) / now.scale,
              (event.clientY - rect.top) / now.scale,
            );
            host.assign(
              await client.select(now.query.revision, now.query.sheet, address),
            );
            await host.render();
            host.focus();
          }),
        );
      },
      options,
    );
    surface.canvas.addEventListener("dblclick", () => host.edit(), options);
    this.handle.addEventListener(
      "pointerdown",
      (event) => this.start(event),
      options,
    );
    this.handle.addEventListener(
      "pointermove",
      (event) => {
        if (this.drag?.id !== event.pointerId) return;
        this.move(this.drag, event.clientX, event.clientY, event.ctrlKey);
      },
      options,
    );
    this.handle.addEventListener(
      "pointerup",
      (event) => {
        const drag = this.drag;
        if (!drag || drag.id !== event.pointerId) return;
        drag.released = true;
        cancelAnimationFrame(this.frame);
        this.frame = 0;
        this.accept(
          this.finish(
            drag,
            { x: event.clientX, y: event.clientY },
            event.ctrlKey,
          ),
        );
      },
      options,
    );
    this.handle.addEventListener("pointercancel", () => this.cancel(), options);
    this.handle.addEventListener(
      "dblclick",
      (event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        this.fillAdjacent(false);
      },
      options,
    );
    this.handle.addEventListener(
      "click",
      (event) => {
        if (event.detail === 0) this.fillAdjacent(true);
      },
      options,
    );
    this.handle.addEventListener(
      "lostpointercapture",
      () => {
        if (!this.drag?.released) this.cancel();
      },
      options,
    );
    this.handle.addEventListener(
      "keydown",
      (event) => {
        const now = host.current();
        if ((event.key === "Enter" || event.key === " ") && !now.disabled) {
          event.preventDefault();
          event.stopPropagation();
          this.fillAdjacent(true);
          return;
        }
        const directions: Record<
          string,
          "up" | "down" | "left" | "right" | undefined
        > = {
          ArrowUp: "up",
          ArrowDown: "down",
          ArrowLeft: now.layout?.rtl ? "right" : "left",
          ArrowRight: now.layout?.rtl ? "left" : "right",
        };
        const direction = directions[event.key];
        const ctrl = event.ctrlKey;
        if (!direction || host.current().disabled) return;
        event.preventDefault();
        event.stopPropagation();
        this.accept(
          this.host.run(async () => {
            await this.prepare(this.source());
            const current = host.current();
            if (!current.layout) return;
            const preview = await client.fillPreview(current.layout.id, {
              kind: "direction",
              direction,
              ctrl,
            });
            await this.apply(this.source(), preview, true);
          }),
        );
      },
      options,
    );
    window.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Control" && this.drag && !this.drag.released) {
          this.drag.ctrl = event.ctrlKey;
          if (this.drag.point)
            this.move(this.drag, this.drag.point.x, this.drag.point.y);
          return;
        }
        if (event.key !== "Escape" || !this.drag) return;
        event.preventDefault();
        event.stopPropagation();
        this.cancel();
      },
      { signal, capture: true },
    );
    window.addEventListener(
      "keyup",
      (event) => {
        if (event.key !== "Control" || !this.drag || this.drag.released) return;
        this.drag.ctrl = event.ctrlKey;
        if (this.drag.point)
          this.move(this.drag, this.drag.point.x, this.drag.point.y);
      },
      options,
    );
    window.addEventListener("blur", () => this.cancel(), options);
    signal.addEventListener("abort", () => this.cancel(false), { once: true });
  }
  private accept(task: Promise<unknown>): void {
    void task.catch((error) => {
      if (!this.signal.aborted) this.host.report(error);
    });
  }
  private fillAdjacent(keyboard: boolean): void {
    if (this.host.current().disabled) return;
    const selected = this.source();
    this.cancel(false);
    this.accept(
      this.host.run(async () => {
        await this.prepare(selected);
        const now = this.host.current();
        if (!now.layout) return;
        const preview = await this.client.fillPreview(now.layout.id, {
          kind: "adjacent",
        });
        await this.apply(this.source(), preview, keyboard);
      }),
    );
  }
  private source(): Source {
    const query = this.host.current().query;
    return {
      revision: query.revision,
      sheet: query.sheet,
      source: query.selection.address,
    };
  }
  private async prepare(selected: Source): Promise<void> {
    await this.host.prepare();
    const query = this.host.current().query;
    if (query.sheet !== selected.sheet) throw new Error("Fill source changed");
    if (query.selection.address !== selected.source) {
      this.host.assign(
        await this.client.select(
          query.revision,
          selected.sheet,
          selected.source,
        ),
      );
      await this.host.render();
    }
  }
  private matches(source: Source, admitted = false): boolean {
    const now = this.host.current();
    return (
      (admitted || !now.disabled) &&
      !this.viewport.hidden &&
      now.query.revision === source.revision &&
      now.query.sheet === source.sheet &&
      now.query.selection.address === source.source
    );
  }
  private paint(geometry: XlsxSelectionGeometry): void {
    const now = this.host.current();
    if (now.layout && !this.signal.aborted)
      paintGridSelection(
        this.surface.clearOverlay(now.scale),
        geometry,
        now.layout,
      );
  }
  update(geometry: XlsxSelectionGeometry): void {
    this.notes.update();
    this.geometry = geometry;
    if (this.pictures.update()) {
      this.handle.hidden = true;
      return;
    }
    const now = this.host.current();
    if (this.drag) {
      if (
        this.drag.source &&
        !this.matches(this.drag.source, this.drag.released)
      )
        this.cancel();
      else if (this.drag.point && !this.drag.released && !this.preparing)
        this.move(this.drag, this.drag.point.x, this.drag.point.y);
      return;
    }
    this.paint(geometry);
    const range = now.query.selection.range;
    const cell = now.layout?.cells.find(
      (item) =>
        item.range.top <= range.bottom &&
        item.range.bottom >= range.bottom &&
        item.range.left <= range.right &&
        item.range.right >= range.right,
    );
    const x =
      cell && (now.layout?.rtl ? cell.rect.x : cell.rect.x + cell.rect.width);
    const y = cell && cell.rect.y + cell.rect.height;
    const visible =
      cell &&
      x !== undefined &&
      y !== undefined &&
      cell.rect.width > 0 &&
      cell.rect.height > 0 &&
      x >= cell.clip.x - 0.01 &&
      x <= cell.clip.x + cell.clip.width + 0.01 &&
      y >= cell.clip.y &&
      y <= cell.clip.y + cell.clip.height + 0.01;
    this.handle.hidden =
      now.disabled ||
      this.viewport.hidden ||
      !visible ||
      !!now.query.readOnlyReason;
    this.handle.style.opacity = "1";
    if (visible) {
      this.handle.style.left = `${x * now.scale - 5}px`;
      this.handle.style.top = `${y * now.scale - 5}px`;
    }
  }
  private start(event: PointerEvent): void {
    event.preventDefault();
    if (event.button !== 0 || this.drag || this.host.current().disabled) return;
    const drag: Drag = {
      id: event.pointerId,
      origin: { x: event.clientX, y: event.clientY },
      ready: Promise.resolve(),
      released: false,
      ctrl: event.ctrlKey,
    };
    this.drag = drag;
    const selected = this.source();
    this.handle.style.opacity = "0";
    this.handle.setPointerCapture(event.pointerId);
    drag.ready = this.host.run(async () => {
      await this.prepare(selected);
      if (this.drag === drag) drag.source = this.source();
    });
    this.accept(
      drag.ready.catch((error) => {
        this.cancel();
        throw error;
      }),
    );
  }
  private move(drag: Drag, x: number, y: number, ctrl = drag.ctrl): void {
    drag.ctrl = ctrl;
    if (!drag.point && Math.hypot(x - drag.origin.x, y - drag.origin.y) < 3)
      return;
    drag.point = drag.pending = { x, y };
    this.accept(this.pump(drag));
    if (!drag.released && !this.frame)
      this.frame = requestAnimationFrame(() => this.scroll(drag));
  }
  private pump(drag: Drag): Promise<void> {
    if (drag.busy) return drag.busy;
    drag.busy = (async () => {
      await drag.ready;
      while (this.drag === drag && !drag.released && drag.pending) {
        const point = drag.pending;
        delete drag.pending;
        const result = await this.host.run(async () => {
          if (!drag.source) throw new Error("Fill source changed");
          return this.preview(drag.source, point, drag.ctrl);
        });
        if (this.drag !== drag) return;
        if (this.host.current().layout?.id !== result.id) {
          drag.pending ??= point;
          continue;
        }
        this.paint(result.preview.geometry);
      }
    })()
      .catch((error) => {
        if (this.drag === drag) {
          this.cancel();
          throw error;
        }
      })
      .finally(() => {
        delete drag.busy;
      });
    return drag.busy;
  }
  private scroll(drag: Drag): void {
    this.frame = 0;
    if (this.drag !== drag || drag.released || !drag.point) return;
    const rect = this.viewport.getBoundingClientRect();
    const dx =
      drag.point.x < rect.left + 24
        ? -16
        : drag.point.x > rect.right - 24
          ? 16
          : 0;
    const dy =
      drag.point.y < rect.top + 24
        ? -16
        : drag.point.y > rect.bottom - 24
          ? 16
          : 0;
    const x = this.viewport.scrollLeft,
      y = this.viewport.scrollTop;
    this.viewport.scrollBy(dx, dy);
    if (
      (dx || dy) &&
      (x !== this.viewport.scrollLeft || y !== this.viewport.scrollTop)
    )
      this.frame = requestAnimationFrame(() => this.scroll(drag));
  }
  private async preview(
    source: Source,
    point: { x: number; y: number },
    ctrl = false,
    admitted = false,
    local = false,
  ) {
    this.preparing = true;
    try {
      await this.host.prepare();
    } finally {
      this.preparing = false;
    }
    if (!this.matches(source, admitted)) throw new Error("Fill source changed");
    const now = this.host.current(),
      layout = now.layout;
    if (!layout) throw new Error("Fill geometry is unavailable");
    const rect = local
      ? { left: 0, top: 0 }
      : this.surface.canvas.getBoundingClientRect();
    const width = layout.regions[0]!.width,
      height = layout.regions[0]!.height;
    const target: XlsxFillTarget = {
      kind: "point",
      ctrl,
      x: Math.max(
        (layout.rtl ? 0 : layout.headerWidth) + 0.001,
        Math.min(
          width - (layout.rtl ? layout.headerWidth : 0) - 0.001,
          (point.x - rect.left) / now.scale,
        ),
      ),
      y: Math.max(
        layout.headerHeight + 0.001,
        Math.min(height - 0.001, (point.y - rect.top) / now.scale),
      ),
    };
    return {
      preview: await this.client.fillPreview(layout.id, target),
      id: layout.id,
    };
  }
  private finish(
    drag: Drag,
    point: { x: number; y: number },
    ctrl: boolean,
  ): Promise<void> {
    // A following save may move the canvas before this queued release executes.
    const rect = this.surface.canvas.getBoundingClientRect();
    const local = { x: point.x - rect.left, y: point.y - rect.top };
    // Admit the release before a following save; no later move may enqueue a preview.
    return this.host.run(async () => {
      if (this.drag !== drag || !drag.source) return;
      if (Math.hypot(point.x - drag.origin.x, point.y - drag.origin.y) < 3) {
        this.cancel(false);
        if (this.geometry) this.update(this.geometry);
        this.host.focus();
        return;
      }
      try {
        const result = await this.preview(drag.source, local, ctrl, true, true);
        this.drag = undefined;
        if (this.handle.hasPointerCapture(drag.id))
          this.handle.releasePointerCapture(drag.id);
        if (this.geometry) this.update(this.geometry);
        await this.apply(drag.source, result.preview, false);
      } finally {
        if (this.drag === drag) {
          this.cancel(false);
          if (this.geometry) this.update(this.geometry);
        }
      }
    });
  }
  private async apply(
    source: Source,
    preview: XlsxFillPreview,
    keyboard: boolean,
  ): Promise<void> {
    if (!this.matches(source, true) || preview.source !== source.source)
      throw new Error("Fill source changed");
    if (preview.mode === "shrink" || preview.range !== source.source) {
      this.host.assign(
        await this.client.editSheet(source.revision, source.sheet, {
          action: "series",
          mode: preview.mode,
          source: source.source,
          range: preview.range,
          direction: preview.direction,
        }),
      );
      {
        const now = this.host.current(),
          layout = now.layout;
        if (layout) {
          const end = preview.end;
          const left = layout.rtl ? 0 : layout.headerWidth,
            right =
              layout.regions[0]!.width - (layout.rtl ? layout.headerWidth : 0);
          const dx =
            end.x < left
              ? end.x - left
              : Math.max(0, end.x + end.width - right);
          const dy =
            end.y < layout.headerHeight
              ? end.y - layout.headerHeight
              : Math.max(0, end.y + end.height - layout.regions[0]!.height);
          this.viewport.scrollBy(
            Math.sign(dx) * Math.ceil(Math.abs(dx * now.scale)),
            Math.sign(dy) * Math.ceil(Math.abs(dy * now.scale)),
          );
        }
      }
      await this.host.render();
    }
    if (keyboard && !this.handle.hidden)
      this.handle.focus({ preventScroll: true });
    else this.host.focus();
  }
  cancel(paint = true): void {
    this.pictures.cancel();
    const drag = this.drag;
    if (paint && drag?.released) return;
    this.drag = undefined;
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    if (drag && this.handle.hasPointerCapture(drag.id))
      this.handle.releasePointerCapture(drag.id);
    if (paint && this.geometry) this.update(this.geometry);
    if (!this.signal.aborted) this.host.changed();
  }
}
