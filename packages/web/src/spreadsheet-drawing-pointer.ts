import type { CanvasSurface } from "./canvas-surface.js";
import type {
  XlsxClient,
  XlsxDrawingGesture,
  XlsxDrawingSelection,
} from "./xlsx.js";
import type { PointerHost } from "./spreadsheet-pointer.js";
import {
  PointerSelection,
  scrollPointerViewport,
  type PointerPoint,
} from "./pointer-selection.js";
import { updateGridScroll } from "./spreadsheet-elements.js";
import {
  copySpreadsheetDrawing,
  cutSpreadsheetDrawing,
} from "./spreadsheet-clipboard.js";

interface Gesture {
  object: string;
  handle: number;
  origin: PointerPoint;
  point: PointerPoint;
  revision: number;
  layout: number;
  scale: number;
  cancelled: boolean;
  ready: boolean;
  viewport: NonNullable<XlsxDrawingGesture["viewport"]>;
}

/** Core selection and candidate drawing; only pointer samples live in this host. */
export class SpreadsheetDrawingPointer {
  private readonly controls = document.createElement("div");
  private readonly targets = new Map<
    string,
    { button: HTMLButtonElement; pointer: PointerSelection; abort(): void }
  >();
  private gesture: Gesture | undefined;
  private ending = false;
  constructor(
    private readonly surface: CanvasSurface,
    holder: HTMLElement,
    private readonly viewport: HTMLElement,
    private readonly spacer: HTMLElement,
    private readonly client: XlsxClient,
    private readonly signal: AbortSignal,
    private readonly host: PointerHost,
  ) {
    holder.append(this.controls);
    window.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && this.active) {
          event.preventDefault();
          event.stopPropagation();
          this.cancel();
        }
      },
      { signal, capture: true },
    );
    viewport.addEventListener(
      "scroll",
      () => {
        if (!this.ownsScroll()) this.cancel();
      },
      { signal },
    );
    viewport.addEventListener("wheel", () => this.cancel(), {
      signal,
      passive: true,
    });
    signal.addEventListener(
      "abort",
      () => {
        this.cancel();
        this.controls.remove();
      },
      { once: true },
    );
  }
  get active(): boolean {
    return this.ending || this.gesture !== undefined;
  }
  ownsScroll(): boolean {
    const gesture = this.gesture;
    return (
      gesture !== undefined &&
      Math.abs(
        Math.abs(this.viewport.scrollLeft) / gesture.scale -
          gesture.viewport.scrollX,
      ) < 0.1 &&
      Math.abs(
        this.viewport.scrollTop / gesture.scale - gesture.viewport.scrollY,
      ) < 0.1
    );
  }
  private report(error: unknown): void {
    if (!this.signal.aborted) this.host.report(error);
  }
  private delta(gesture: Gesture) {
    return {
      viewport: { ...gesture.viewport },
      dx: Math.max(
        -14400,
        Math.min(14400, (gesture.point.x - gesture.origin.x) / gesture.scale),
      ),
      dy: Math.max(
        -14400,
        Math.min(14400, (gesture.point.y - gesture.origin.y) / gesture.scale),
      ),
    };
  }
  private target(
    key: string,
    object: string,
    handle: number,
    label: string,
  ): HTMLButtonElement {
    const known = this.targets.get(key);
    if (known) {
      known.button.setAttribute("aria-label", label);
      return known.button;
    }
    const button = document.createElement("button");
    const scope = new AbortController();
    const abort = () => {
      this.signal.removeEventListener("abort", abort);
      scope.abort();
    };
    this.signal.addEventListener("abort", abort, { once: true });
    button.type = "button";
    button.setAttribute("aria-label", label);
    button.setAttribute(
      "aria-keyshortcuts",
      this.host
        .current()
        .layout?.objects.some(
          (item) => item.id === object && (item.slicer || item.timeline),
        )
        ? "ArrowLeft ArrowRight ArrowUp ArrowDown Delete Escape"
        : "ArrowLeft ArrowRight ArrowUp ArrowDown Delete Escape Control+X Meta+X Control+C Meta+C",
    );
    Object.assign(button.style, {
      position: "absolute",
      padding: "0",
      margin: "0",
      border: "0",
      background: handle ? "#2563eb" : "transparent",
      cursor: handle ? (handle % 2 ? "nwse-resize" : "nesw-resize") : "move",
      zIndex: handle ? "5" : "4",
      touchAction: "none",
    });
    this.controls.append(button);
    const pointer = new PointerSelection(
      button,
      this.viewport,
      scope.signal,
      async (point, initial, _extend, elapsed) => {
        if (initial) {
          const now = this.host.current();
          if (!now.layout) return;
          const sheet = now.query.sheet;
          const rect = this.surface.canvas.getBoundingClientRect();
          const gesture: Gesture = {
            object,
            handle,
            origin: point,
            point,
            revision: now.query.revision,
            layout: now.layout.id,
            scale: now.scale,
            cancelled: false,
            ready: false,
            viewport: {
              originX: (point.x - rect.left) / now.scale,
              originY: (point.y - rect.top) / now.scale,
              scrollX: Math.abs(this.viewport.scrollLeft) / now.scale,
              scrollY: this.viewport.scrollTop / now.scale,
            },
          };
          this.gesture = gesture;
          this.host.changed();
          return this.host
            .run(async () => {
              await this.host.prepare();
              const current = this.host.current();
              if (gesture.cancelled || !current.layout) return;
              if (current.query.sheet !== sheet)
                throw new Error("Worksheet object target changed");
              gesture.revision = current.query.revision;
              gesture.layout = current.layout.id;
              gesture.ready = true;
              const selection = await this.client.selectDrawing(
                gesture.revision,
                gesture.layout,
                object,
              );
              this.paint(selection);
            })
            .catch((error) => {
              this.cancel();
              this.report(error);
            });
        }
        const gesture = this.gesture;
        if (!gesture) return;
        gesture.point = point;
        return this.host
          .run(async () => {
            if (gesture.cancelled || this.gesture !== gesture) return;
            if (!this.ending)
              scrollPointerViewport(
                this.viewport,
                point,
                elapsed,
                performance.now(),
              );
            gesture.viewport.scrollX =
              Math.abs(this.viewport.scrollLeft) / gesture.scale;
            gesture.viewport.scrollY = this.viewport.scrollTop / gesture.scale;
            const preview = await this.client.drawingGesture(
              gesture.revision,
              gesture.layout,
              { handle, ...this.delta(gesture), commit: false },
              this.host.current().profile,
            );
            if (gesture.cancelled || this.signal.aborted) return;
            if (preview.drawing) {
              this.surface.draw(preview.drawing, 0, (gesture.scale * 72) / 96);
              updateGridScroll(
                this.viewport,
                this.spacer,
                preview.drawing,
                gesture.scale,
              );
              gesture.viewport.scrollX =
                Math.abs(this.viewport.scrollLeft) / gesture.scale;
              gesture.viewport.scrollY =
                this.viewport.scrollTop / gesture.scale;
            }
            this.paint(preview.selection);
          })
          .catch((error) => {
            this.cancel();
            this.report(error);
          });
      },
      () => !this.host.current().disabled && !this.active,
      async (cancelled) => {
        const gesture = this.gesture;
        if (!gesture) return;
        if (cancelled) gesture.cancelled = true;
        this.ending = true;
        try {
          await this.host.run(async () => {
            if (!gesture.cancelled) {
              const result = await this.client.drawingGesture(
                gesture.revision,
                gesture.layout,
                { handle, ...this.delta(gesture), commit: true },
                this.host.current().profile,
              );
              if (result.query) this.host.assign(result.query);
            }
            this.gesture = undefined;
            this.ending = false;
            await this.host.render();
          });
        } catch (error) {
          this.report(error);
        } finally {
          this.gesture = undefined;
          this.ending = false;
          this.host.changed();
        }
      },
    );
    button.addEventListener(
      "keydown",
      (event) => {
        if (
          (event.ctrlKey || event.metaKey) &&
          !event.altKey &&
          !event.shiftKey &&
          ["x", "c"].includes(event.key.toLowerCase())
        ) {
          event.preventDefault();
          event.stopPropagation();
          if (this.active || this.host.current().disabled) return;
          if (
            this.host
              .current()
              .layout?.objects.some(
                (item) => item.id === object && (item.slicer || item.timeline),
              )
          )
            return;
          const sheet = this.host.current().query.sheet;
          void this.host
            .run(async () => {
              await this.host.prepare();
              if (this.host.current().query.sheet !== sheet)
                throw new Error("Worksheet object target changed");
              if (event.key.toLowerCase() === "x")
                await cutSpreadsheetDrawing(
                  this.client,
                  this.host.current().query,
                  object,
                );
              else
                await copySpreadsheetDrawing(
                  this.client,
                  this.host.current().query,
                  object,
                  this.host.current().profile,
                );
            })
            .catch((error) => this.report(error));
          return;
        }
        const step = event.shiftKey ? 10 : 1;
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
        if (
          (!dx && !dy && event.key !== "Delete") ||
          this.active ||
          this.host.current().disabled
        )
          return;
        event.preventDefault();
        event.stopPropagation();
        const sheet = this.host.current().query.sheet;
        void this.host
          .run(async () => {
            await this.host.prepare();
            const now = this.host.current();
            if (now.query.sheet !== sheet)
              throw new Error("Worksheet object target changed");
            if (!now.layout) return;
            await this.client.selectDrawing(
              now.query.revision,
              now.layout.id,
              object,
            );
            if (event.key === "Delete") {
              const target = now.layout.objects.find(
                (item) => item.id === object,
              );
              if (!target) throw new Error("Worksheet object no longer exists");
              this.host.assign(
                await (target.timeline
                  ? this.client.editSheet(now.query.revision, now.query.sheet, {
                      action: "deleteTimeline",
                      name: target.timeline.name,
                    })
                  : target.slicer
                    ? this.client.editSheet(
                        now.query.revision,
                        now.query.sheet,
                        {
                          action: "deleteSlicer",
                          name: target.slicer.name,
                        },
                      )
                    : target.kind === "picture"
                      ? this.client.deletePicture(
                          now.query.revision,
                          now.query.sheet,
                          object,
                          now.profile,
                        )
                      : target.kind === "chart"
                        ? this.client.deleteChart(
                            now.query.revision,
                            now.query.sheet,
                            object,
                            now.profile,
                          )
                        : this.client.deleteShape(
                            now.query.revision,
                            now.query.sheet,
                            object,
                            now.profile,
                          )),
              );
            } else {
              const result = await this.client.drawingGesture(
                now.query.revision,
                now.layout.id,
                { handle, dx, dy, commit: true },
                now.profile,
              );
              if (result.query) this.host.assign(result.query);
            }
            await this.host.render();
          })
          .catch((error) => this.report(error));
      },
      { signal: scope.signal },
    );
    button.addEventListener(
      "click",
      (event) => {
        if (event.detail !== 0 || this.active || this.host.current().disabled)
          return;
        const sheet = this.host.current().query.sheet;
        void this.host
          .run(async () => {
            await this.host.prepare();
            const now = this.host.current();
            if (now.query.sheet !== sheet)
              throw new Error("Worksheet object target changed");
            if (now.layout)
              await this.client.selectDrawing(
                now.query.revision,
                now.layout.id,
                object,
              );
            await this.host.render();
          })
          .catch((error) => this.report(error));
      },
      { signal: scope.signal },
    );
    this.targets.set(key, { button, pointer, abort });
    return button;
  }
  private paint(selection: XlsxDrawingSelection): void {
    const context = this.surface.clearOverlay(this.host.current().scale);
    context.strokeStyle = "#2563eb";
    context.lineWidth = 1;
    for (const region of selection.regions) {
      context.save();
      context.beginPath();
      context.rect(
        region.clip.x,
        region.clip.y,
        region.clip.width,
        region.clip.height,
      );
      context.clip();
      context.strokeRect(
        region.rect.x,
        region.rect.y,
        region.rect.width,
        region.rect.height,
      );
      context.restore();
    }
  }
  update(blocked = false): boolean {
    this.controls.hidden = blocked;
    if (blocked) return true;
    if (this.active) {
      if (
        this.gesture?.ready &&
        this.host.current().layout?.id !== this.gesture.layout
      )
        this.cancel();
      return true;
    }
    const now = this.host.current(),
      seen = new Set<string>();
    let selected = false;
    if (now.layout && !this.viewport.hidden && !now.disabled)
      for (const [layer, object] of now.layout.objects.entries()) {
        for (const [index, region] of (
          object.timeline?.move ??
          object.slicer?.move ??
          object.regions
        ).entries()) {
          const key = `${object.id}:${index}:move`,
            button = this.target(
              key,
              object.id,
              0,
              `Move object ${object.name}`,
            );
          seen.add(key);
          Object.assign(button.style, {
            left: `${region.clip.x * now.scale}px`,
            top: `${region.clip.y * now.scale}px`,
            width: `${region.clip.width * now.scale}px`,
            height: `${region.clip.height * now.scale}px`,
            zIndex: String(layer + 4),
            outline: object.selected ? "1px solid #2563eb" : "none",
          });
        }
        if (!object.selected) continue;
        selected = true;
        if (object.slicer || object.timeline)
          this.paint({
            revision: now.query.revision,
            sheet: now.query.sheet,
            id: object.id,
            regions: object.regions,
          });
        for (const [index, region] of object.regions.entries()) {
          for (const [corner, name] of [
            "top left",
            "top right",
            "bottom right",
            "bottom left",
          ].entries()) {
            const x =
                region.rect.x +
                (corner === 1 || corner === 2 ? region.rect.width : 0),
              y = region.rect.y + (corner >= 2 ? region.rect.height : 0);
            if (
              x < region.clip.x - 0.001 ||
              x > region.clip.x + region.clip.width + 0.001 ||
              y < region.clip.y - 0.001 ||
              y > region.clip.y + region.clip.height + 0.001
            )
              continue;
            const key = `${object.id}:${index}:${corner}`,
              button = this.target(
                key,
                object.id,
                corner + 1,
                `Resize worksheet object ${name}`,
              );
            seen.add(key);
            Object.assign(button.style, {
              left: `${x * now.scale - 5}px`,
              top: `${y * now.scale - 5}px`,
              width: "10px",
              height: "10px",
              zIndex: String(now.layout.objects.length + 4),
              border: "1px solid white",
            });
          }
        }
      }
    for (const [key, target] of this.targets)
      if (!seen.has(key)) {
        target.pointer.cancel();
        target.abort();
        target.button.remove();
        this.targets.delete(key);
      }
    return selected;
  }
  cancel(): void {
    if (!this.gesture) return;
    this.gesture.cancelled = true;
    for (const target of this.targets.values()) target.pointer.finish(true);
  }
}
