import type { XlsxClient } from "./xlsx.js";
import type { PointerHost } from "./spreadsheet-pointer.js";
import type { CanvasSurface } from "./canvas-surface.js";
import { PointerSelection, type PointerPoint } from "./pointer-selection.js";
import { paintTimelineEndpoints } from "./spreadsheet-timeline-endpoints.js";
import type { XlsxViewport } from "@open-document/wasm/xlsx";

interface DateGesture {
  object: string;
  handle: number;
  first: number;
  position: number;
  group: HTMLElement;
  moved: boolean;
  timer: number | undefined;
  sheet: string;
  revision: number;
  layout: number;
  point: PointerPoint;
  left: number;
  top: number;
  scale: number;
  ready: boolean;
  cancelled: boolean;
}

export class SpreadsheetTimelinePointer {
  private readonly dateTargets = new Map<
    string,
    { pointer: PointerSelection; abort(): void }
  >();
  private dateGesture: DateGesture | undefined;
  private dateEnding = false;
  constructor(
    private readonly surface: CanvasSurface,
    private readonly viewport: HTMLElement,
    private readonly client: XlsxClient,
    private readonly signal: AbortSignal,
    private readonly host: PointerHost,
  ) {}
  get active(): boolean {
    return this.dateGesture !== undefined || this.dateEnding;
  }
  cancel(): void {
    if (!this.dateGesture) return;
    this.dateGesture.cancelled = true;
    clearTimeout(this.dateGesture.timer);
    for (const target of this.dateTargets.values()) target.pointer.finish(true);
  }
  private async dateSample(
    gesture: DateGesture,
    commit: boolean,
  ): Promise<void> {
    if (gesture.cancelled || this.dateGesture !== gesture) return;
    clearTimeout(gesture.timer);
    gesture.timer = undefined;
    const result = await this.client.timelineGesture(
      gesture.revision,
      gesture.layout,
      gesture.object,
      {
        handle: gesture.handle,
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
        commit,
      },
      this.host.current().profile,
    );
    if (gesture.cancelled || this.signal.aborted) return;
    if (result.query) this.host.assign(result.query);
    if (result.drawing) {
      this.surface.draw(result.drawing, 0, (gesture.scale * 72) / 96);
      paintTimelineEndpoints(
        this.surface,
        result.drawing,
        gesture.object,
        gesture.scale,
      );
      for (const target of gesture.group.querySelectorAll<HTMLButtonElement>(
        "button[data-timeline-endpoint]",
      ))
        target.style.background = "transparent";
      this.schedule(gesture, result.drawing);
    }
  }
  private schedule(gesture: DateGesture, drawing: XlsxViewport): void {
    if (!gesture.moved || this.dateEnding || gesture.cancelled) return;
    const timeline = drawing.objects.find(
      (item) => item.id === gesture.object,
    )?.timeline;
    if (!timeline) return;
    const x = (gesture.point.x - gesture.left) / gesture.scale,
      y = (gesture.point.y - gesture.top) / gesture.scale;
    const clips = timeline.periods
      .flatMap((period) => period.regions.map((region) => region.clip))
      .filter((clip) => y >= clip.y - 16 && y <= clip.y + clip.height + 16);
    if (!clips.length) return;
    const left = Math.min(...clips.map((clip) => clip.x)),
      right = Math.max(...clips.map((clip) => clip.x + clip.width)),
      direction = x < left + 6 ? -1 : x > right - 6 ? 1 : 0;
    const navigation = timeline.navigation,
      next = Math.max(
        navigation.minimum,
        Math.min(navigation.maximum, navigation.position + direction),
      );
    if (next === navigation.position) return;
    gesture.timer = window.setTimeout(() => {
      gesture.timer = undefined;
      if (this.dateGesture !== gesture || gesture.cancelled || this.dateEnding)
        return;
      void this.host
        .run(async () => {
          if (
            this.dateGesture !== gesture ||
            gesture.cancelled ||
            this.dateEnding
          )
            return;
          gesture.position = next;
          await this.dateSample(gesture, false);
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
    handle: number,
  ): void {
    if (this.dateTargets.has(key)) return;
    const scope = new AbortController();
    const abort = () => {
      this.signal.removeEventListener("abort", abort);
      scope.abort();
    };
    this.signal.addEventListener("abort", abort, { once: true });
    const pointer = new PointerSelection(
      button,
      this.viewport,
      scope.signal,
      async (point, initial) => {
        if (initial) {
          const now = this.host.current();
          const gesture: DateGesture = {
            object,
            handle,
            first,
            position: -1,
            group: button.parentElement ?? button,
            moved: false,
            timer: undefined,
            sheet: now.query.sheet,
            revision: now.query.revision,
            layout: now.layout?.id ?? -1,
            point,
            left: 0,
            top: 0,
            scale: now.scale,
            ready: false,
            cancelled: false,
          };
          this.dateGesture = gesture;
          this.host.changed();
          return this.host
            .run(async () => {
              await this.host.prepare();
              const current = this.host.current(),
                rect = this.surface.canvas.getBoundingClientRect();
              if (gesture.cancelled) return;
              if (!current.layout || current.query.sheet !== gesture.sheet)
                throw new Error("Timeline target changed");
              gesture.revision = current.query.revision;
              gesture.layout = current.layout.id;
              const timeline = current.layout.objects.find(
                (item) => item.id === object,
              )?.timeline;
              if (!timeline) throw new Error("Timeline target changed");
              gesture.position = timeline.navigation.position;
              gesture.left = rect.left;
              gesture.top = rect.top;
              gesture.scale = current.scale;
              gesture.ready = true;
              await this.dateSample(gesture, false);
            })
            .catch((error: unknown) => {
              this.cancel();
              this.host.report(error);
            });
        }
        const gesture = this.dateGesture;
        if (!gesture) return;
        gesture.point = point;
        gesture.moved = true;
        return this.host
          .run(() => this.dateSample(gesture, false))
          .catch((error: unknown) => {
            this.cancel();
            this.host.report(error);
          });
      },
      () => !this.host.current().disabled && !this.active,
      async (cancelled) => {
        const gesture = this.dateGesture;
        if (!gesture) return;
        if (cancelled) gesture.cancelled = true;
        this.dateEnding = true;
        clearTimeout(gesture.timer);
        try {
          await this.host.run(async () => {
            try {
              await this.dateSample(gesture, true);
            } finally {
              this.dateGesture = undefined;
              this.dateEnding = false;
              if (!this.signal.aborted) await this.host.render();
            }
          });
        } catch (error) {
          if (!this.signal.aborted) this.host.report(error);
        } finally {
          this.dateGesture = undefined;
          this.dateEnding = false;
          this.host.changed();
        }
      },
      false,
    );
    this.dateTargets.set(key, { pointer, abort });
  }
  select(object: string, first: number): void {
    const sheet = this.host.current().query.sheet;
    void this.host
      .run(async () => {
        await this.host.prepare();
        const now = this.host.current(),
          layout = now.layout;
        if (!layout || now.query.sheet !== sheet)
          throw new Error("Timeline target changed");
        const region = layout.objects
          .find((item) => item.id === object)
          ?.timeline?.periods.find((period) => period.index === first)
          ?.regions[0];
        if (!region) throw new Error("Timeline period is no longer visible");
        const result = await this.client.timelineGesture(
          now.query.revision,
          layout.id,
          object,
          {
            handle: 0,
            first,
            position:
              layout.objects.find((item) => item.id === object)?.timeline
                ?.navigation.position ?? -1,
            x: region.clip.x + region.clip.width / 2,
            y: region.clip.y + region.clip.height / 2,
            commit: true,
          },
          now.profile,
        );
        if (result.query) this.host.assign(result.query);
        await this.host.render();
      })
      .catch((error: unknown) => {
        if (!this.signal.aborted) this.host.report(error);
      });
  }
  checkLayout(): void {
    if (
      this.dateGesture?.ready &&
      this.host.current().layout?.id !== this.dateGesture.layout
    )
      this.cancel();
  }
  remove(key: string): void {
    const date = this.dateTargets.get(key);
    date?.pointer.cancel();
    date?.abort();
    this.dateTargets.delete(key);
  }
}
