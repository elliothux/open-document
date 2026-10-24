import type { XlsxClient } from "./xlsx.js";
import type { PointerHost } from "./spreadsheet-pointer.js";
import type { CanvasSurface } from "./canvas-surface.js";
import type { XlsxViewport } from "@open-document/wasm/xlsx";
import { PointerSelection, type PointerPoint } from "./pointer-selection.js";

interface MemberGesture {
  object: string;
  first: number;
  additive: boolean;
  multi: boolean;
  position: number;
  sheet: string;
  revision: number;
  layout: number;
  point: PointerPoint;
  left: number;
  top: number;
  scale: number;
  ready: boolean;
  moved: boolean;
  cancelled: boolean;
  timer?: number;
}

/** Pointer capture and events use the core's ordered native member selection. */
export class SpreadsheetSlicerPointer {
  private readonly targets = new Map<
    string,
    { pointer: PointerSelection; abort(): void }
  >();
  private gesture: MemberGesture | undefined;
  private ending = false;
  constructor(
    private readonly surface: CanvasSurface,
    private readonly viewport: HTMLElement,
    private readonly client: XlsxClient,
    private readonly signal: AbortSignal,
    private readonly host: PointerHost,
  ) {
    const modifiers = (event: KeyboardEvent) => {
      const gesture = this.gesture;
      if (!gesture || this.ending || !["Control", "Meta"].includes(event.key))
        return;
      const additive = event.ctrlKey || event.metaKey || gesture.multi;
      if (gesture.additive === additive) return;
      event.preventDefault();
      event.stopPropagation();
      gesture.additive = additive;
      void this.host
        .run(() => this.sample(gesture, false))
        .catch((error: unknown) => {
          this.cancel();
          if (!this.signal.aborted) this.host.report(error);
        });
    };
    window.addEventListener("keydown", modifiers, { signal, capture: true });
    window.addEventListener("keyup", modifiers, { signal, capture: true });
  }
  get active(): boolean {
    return this.gesture !== undefined || this.ending;
  }
  cancel(): void {
    if (!this.gesture) return;
    this.gesture.cancelled = true;
    clearTimeout(this.gesture.timer);
    for (const target of this.targets.values()) target.pointer.finish(true);
  }
  private async sample(gesture: MemberGesture, commit: boolean): Promise<void> {
    if (gesture.cancelled || this.gesture !== gesture) return;
    clearTimeout(gesture.timer);
    delete gesture.timer;
    const result = await this.client.slicerGesture(
      gesture.revision,
      gesture.layout,
      gesture.object,
      {
        first: gesture.first,
        position: gesture.position,
        x: Math.max(
          -14400,
          Math.min(14400, (gesture.point.x - gesture.left) / gesture.scale),
        ),
        y: Math.max(
          -14400,
          Math.min(14400, (gesture.point.y - gesture.top) / gesture.scale),
        ),
        additive: gesture.additive,
        commit,
      },
      this.host.current().profile,
    );
    if (gesture.cancelled || this.signal.aborted) return;
    if (result.query) this.host.assign(result.query);
    if (result.drawing) {
      this.surface.draw(result.drawing, 0, (gesture.scale * 72) / 96);
      this.schedule(gesture, result.drawing);
    }
  }
  private schedule(gesture: MemberGesture, drawing: XlsxViewport): void {
    if (!gesture.moved || this.ending || gesture.cancelled) return;
    const view = drawing.objects.find(
      (object) => object.id === gesture.object,
    )?.slicer;
    if (!view || !view.maximum) return;
    const x = (gesture.point.x - gesture.left) / gesture.scale,
      y = (gesture.point.y - gesture.top) / gesture.scale,
      clips = view.buttons
        .flatMap((button) => button.regions.map((region) => region.clip))
        .filter((clip) => x >= clip.x - 16 && x <= clip.x + clip.width + 16);
    if (!clips.length) return;
    const top = Math.min(...clips.map((clip) => clip.y)),
      bottom = Math.max(...clips.map((clip) => clip.y + clip.height)),
      direction = y < top + 6 ? -1 : y > bottom - 6 ? 1 : 0,
      next = Math.max(0, Math.min(view.maximum, view.start + direction));
    if (next === view.start) return;
    gesture.timer = window.setTimeout(() => {
      delete gesture.timer;
      if (this.gesture !== gesture || gesture.cancelled || this.ending) return;
      void this.host
        .run(async () => {
          if (this.gesture !== gesture || gesture.cancelled || this.ending)
            return;
          gesture.position = next;
          await this.sample(gesture, false);
        })
        .catch((error: unknown) => {
          this.cancel();
          if (!this.signal.aborted) this.host.report(error);
        });
    }, 120);
  }
  bind(
    key: string,
    button: HTMLButtonElement,
    object: string,
    first: number,
    multi: () => boolean,
  ): void {
    if (this.targets.has(key)) return;
    const scope = new AbortController(),
      abort = () => {
        this.signal.removeEventListener("abort", abort);
        scope.abort();
      };
    const group = button.parentElement;
    this.signal.addEventListener("abort", abort, { once: true });
    let additive = false,
      multiple = false;
    button.addEventListener(
      "pointerdown",
      (event) => {
        multiple = multi();
        additive = event.ctrlKey || event.metaKey || multiple;
      },
      { signal: scope.signal },
    );
    const pointer = new PointerSelection(
      button,
      this.viewport,
      scope.signal,
      async (point, initial) => {
        if (initial) {
          const now = this.host.current(),
            gesture: MemberGesture = {
              object,
              first,
              additive,
              multi: multiple,
              position: 0,
              sheet: now.query.sheet,
              revision: now.query.revision,
              layout: now.layout?.id ?? -1,
              point,
              left: 0,
              top: 0,
              scale: now.scale,
              ready: false,
              moved: false,
              cancelled: false,
            };
          this.gesture = gesture;
          this.host.changed();
          return this.host
            .run(async () => {
              await this.host.prepare();
              const current = this.host.current(),
                rect = this.surface.canvas.getBoundingClientRect();
              if (gesture.cancelled) return;
              const view = current.layout?.objects.find(
                (item) => item.id === object,
              )?.slicer;
              if (
                !current.layout ||
                current.query.sheet !== gesture.sheet ||
                !view
              )
                throw new Error("Slicer target changed");
              gesture.revision = current.query.revision;
              gesture.layout = current.layout.id;
              gesture.position = view.start;
              gesture.left = rect.left;
              gesture.top = rect.top;
              gesture.scale = current.scale;
              gesture.ready = true;
              await this.sample(gesture, false);
            })
            .catch((error: unknown) => {
              this.cancel();
              this.host.report(error);
            });
        }
        const gesture = this.gesture;
        if (!gesture) return;
        gesture.point = point;
        gesture.moved = true;
        return this.host
          .run(() => this.sample(gesture, false))
          .catch((error: unknown) => {
            this.cancel();
            this.host.report(error);
          });
      },
      () => !this.host.current().disabled && !this.active,
      async (cancelled) => {
        const gesture = this.gesture;
        if (!gesture) return;
        if (cancelled) gesture.cancelled = true;
        this.ending = true;
        clearTimeout(gesture.timer);
        try {
          await this.host.run(async () => {
            try {
              await this.sample(gesture, true);
            } finally {
              this.gesture = undefined;
              this.ending = false;
              if (!this.signal.aborted) {
                await this.host.render();
                (button.isConnected && !button.disabled
                  ? button
                  : group?.querySelector<HTMLButtonElement>(
                      'button[data-slicer-member="true"]:not(:disabled)',
                    )
                )?.focus({ preventScroll: true });
              }
            }
          });
        } catch (error) {
          if (!this.signal.aborted) this.host.report(error);
        } finally {
          this.gesture = undefined;
          this.ending = false;
          this.host.changed();
        }
      },
      false,
    );
    this.targets.set(key, { pointer, abort });
  }
  checkLayout(): void {
    if (
      this.gesture?.ready &&
      this.host.current().layout?.id !== this.gesture.layout
    )
      this.cancel();
  }
  remove(key: string): void {
    const target = this.targets.get(key);
    target?.pointer.cancel();
    target?.abort();
    this.targets.delete(key);
  }
}
