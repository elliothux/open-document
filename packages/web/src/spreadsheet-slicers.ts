import type { XlsxClient } from "./xlsx.js";
import type { XlsxSlicerView } from "@open-document/wasm/xlsx";
import type { PointerHost } from "./spreadsheet-pointer.js";
import type { CanvasSurface } from "./canvas-surface.js";
import { PointerSelection, type PointerPoint } from "./pointer-selection.js";
import {
  stepTimelineEndpoint,
  paintTimelineEndpoints,
} from "./spreadsheet-timeline-endpoints.js";

interface DateGesture {
  object: string;
  handle: number;
  first: number;
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

type Intent =
  | { kind: "select"; index: number | null; additive: boolean }
  | { kind: "scroll"; rows: number };

/** Native controls use core geometry and the existing worksheet command queue. */
export class SpreadsheetSlicers {
  private readonly controls = document.createElement("div");
  private readonly groups = new Map<string, HTMLDivElement>();
  private readonly targets = new Map<string, HTMLElement>();
  private readonly multi = new Set<string>();
  private readonly dateTargets = new Map<
    string,
    { pointer: PointerSelection; abort(): void }
  >();
  private dateGesture: DateGesture | undefined;
  private dateEnding = false;
  constructor(
    private readonly surface: CanvasSurface,
    holder: HTMLElement,
    private readonly viewport: HTMLElement,
    private readonly client: XlsxClient,
    private readonly signal: AbortSignal,
    private readonly host: PointerHost,
  ) {
    holder.append(this.controls);
    signal.addEventListener(
      "abort",
      () => {
        this.cancel();
        this.controls.remove();
      },
      {
        once: true,
      },
    );
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
    viewport.addEventListener("scroll", () => this.cancel(), { signal });
    viewport.addEventListener("wheel", () => this.cancel(), {
      signal,
      passive: true,
    });
  }
  get active(): boolean {
    return this.dateGesture !== undefined || this.dateEnding;
  }
  cancel(): void {
    if (!this.dateGesture) return;
    this.dateGesture.cancelled = true;
    for (const target of this.dateTargets.values()) target.pointer.finish(true);
  }
  private async dateSample(
    gesture: DateGesture,
    commit: boolean,
  ): Promise<void> {
    if (gesture.cancelled || this.dateGesture !== gesture) return;
    const result = await this.client.timelineGesture(
      gesture.revision,
      gesture.layout,
      gesture.object,
      {
        handle: gesture.handle,
        first: gesture.first,
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
      for (const [key, target] of this.targets)
        if (key.startsWith(`${gesture.object}:endpoint:`))
          target.style.background = "transparent";
    }
  }
  private dateTarget(
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
  private selectDate(object: string, first: number): void {
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
  private navigateTimeline(
    object: string,
    value: number,
    level?: number,
  ): void {
    const sheet = this.host.current().query.sheet;
    void this.host
      .run(async () => {
        await this.host.prepare();
        const now = this.host.current(),
          timeline = now.layout?.objects.find(
            (item) => item.id === object,
          )?.timeline;
        if (now.query.sheet !== sheet || !timeline)
          throw new Error("Timeline view target changed");
        this.host.assign(
          await this.client.editSheet(
            now.query.revision,
            sheet,
            level === undefined
              ? {
                  action: "setTimelineLevel",
                  name: timeline.name,
                  level: value,
                }
              : {
                  action: "scrollTimeline",
                  name: timeline.name,
                  level,
                  position: value,
                },
          ),
        );
        await this.host.render();
      })
      .catch((error: unknown) => {
        if (!this.signal.aborted) this.host.report(error);
      });
  }
  private stepEndpoint(object: string, handle: number, key: string): void {
    void stepTimelineEndpoint(this.client, this.host, object, handle, key)
      .then(() => {
        const target = this.groups
          .get(object)
          ?.querySelector<HTMLButtonElement>(
            `button[data-timeline-endpoint="${handle}"]`,
          );
        if (target) target.focus({ preventScroll: true });
        else this.host.focus();
      })
      .catch((error: unknown) => {
        if (!this.signal.aborted) this.host.report(error);
      });
  }
  private navigationTarget(
    key: string,
    group: HTMLElement,
    object: string,
    level?: number,
  ): HTMLSelectElement | HTMLInputElement {
    const known = this.targets.get(key);
    if (known instanceof HTMLSelectElement || known instanceof HTMLInputElement)
      return known;
    const target =
      level === undefined
        ? document.createElement("select")
        : document.createElement("input");
    if (target instanceof HTMLSelectElement)
      for (const [value, label] of [
        "Years",
        "Quarters",
        "Months",
        "Days",
      ].entries()) {
        const option = document.createElement("option");
        option.value = String(value);
        option.textContent = label;
        target.append(option);
      }
    else {
      target.type = "range";
      target.step = "1";
    }
    target.setAttribute(
      "aria-label",
      level === undefined ? "Timeline display level" : "Timeline start period",
    );
    Object.assign(target.style, {
      position: "absolute",
      padding: "0",
      margin: "0",
      border: "0",
      background: level === undefined ? "white" : "transparent",
      touchAction: "none",
    });
    target.addEventListener("change", () =>
      this.navigateTimeline(object, Number(target.value), level),
    );
    group.append(target);
    this.targets.set(key, target);
    return target;
  }
  private command(id: string, intent: Intent): void {
    const sheet = this.host.current().query.sheet;
    const root = this.controls.getRootNode();
    const focused =
      root instanceof ShadowRoot ? root.activeElement : document.activeElement;
    const restoreFocus =
      focused instanceof HTMLElement && this.controls.contains(focused);
    void this.host
      .run(async () => {
        await this.host.prepare();
        let now = this.host.current();
        if (now.disabled || now.query.sheet !== sheet) return;
        if (now.layout?.revision !== now.query.revision) {
          await this.host.render();
          now = this.host.current();
        }
        const layout = now.layout;
        if (
          !layout?.objects.some((object) => object.id === id && object.slicer)
        )
          return;
        this.host.assign(
          await this.client.editSheet(
            now.query.revision,
            sheet,
            intent.kind === "scroll"
              ? {
                  action: "scrollSlicer",
                  layout: layout.id,
                  id,
                  rows: intent.rows,
                }
              : {
                  action: "selectSlicer",
                  layout: layout.id,
                  id,
                  index: intent.index,
                  additive: intent.additive,
                },
          ),
        );
        await this.host.render();
        if (restoreFocus) {
          const group = this.groups.get(id);
          (
            (focused instanceof HTMLButtonElement &&
            focused.isConnected &&
            !focused.disabled
              ? focused
              : undefined) ??
            group?.querySelector<HTMLButtonElement>(
              'button[data-slicer-member="true"]:not(:disabled)',
            ) ??
            group?.querySelector<HTMLButtonElement>("button:not(:disabled)")
          )?.focus({ preventScroll: true });
        }
      })
      .catch((error) => {
        if (!this.signal.aborted) this.host.report(error);
      });
  }
  private group(id: string): HTMLDivElement {
    const existing = this.groups.get(id);
    if (existing) return existing;
    const group = document.createElement("div");
    group.setAttribute("role", "group");
    group.addEventListener("pointerdown", (event) => event.stopPropagation());
    group.addEventListener("keydown", (event) => {
      event.stopPropagation();
      const view = this.host
        .current()
        .layout?.objects.find((object) => object.id === id)?.slicer;
      if (event.key === "Escape") {
        event.preventDefault();
        this.host.focus();
      } else if (!view) return;
      else if (
        (event.ctrlKey || event.metaKey) &&
        event.key.toLowerCase() === "a" &&
        view.clear.length
      ) {
        event.preventDefault();
        this.command(id, { kind: "select", index: null, additive: false });
      } else if (
        view.maximum > 0 &&
        ["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(
          event.key,
        )
      ) {
        event.preventDefault();
        const rows =
          event.key === "Home"
            ? -4096
            : event.key === "End"
              ? 4096
              : (event.key.endsWith("Up") ? -1 : 1) *
                (event.key.startsWith("Page") ? view.page : 1);
        this.command(id, { kind: "scroll", rows });
      }
    });
    group.addEventListener(
      "wheel",
      (event) => {
        const view = this.host
          .current()
          .layout?.objects.find((object) => object.id === id)?.slicer;
        if (!view || view.maximum === 0 || !event.deltaY) return;
        event.preventDefault();
        event.stopPropagation();
        this.command(id, { kind: "scroll", rows: event.deltaY > 0 ? 1 : -1 });
      },
      { passive: false },
    );
    this.groups.set(id, group);
    this.controls.append(group);
    return group;
  }
  private target(
    key: string,
    group: HTMLElement,
    button: boolean,
    click?: (event: MouseEvent) => void,
  ): HTMLElement {
    const existing = this.targets.get(key);
    if (existing) return existing;
    const target = document.createElement(button ? "button" : "div");
    if (target instanceof HTMLButtonElement) {
      target.type = "button";
      target.addEventListener("click", (event) => {
        event.stopPropagation();
        click?.(event);
      });
      target.addEventListener("focus", () => {
        target.style.outline = "2px solid #2563eb";
      });
      target.addEventListener("blur", () => {
        target.style.outline = "none";
      });
    } else target.setAttribute("aria-hidden", "true");
    Object.assign(target.style, {
      position: "absolute",
      padding: "0",
      margin: "0",
      border: "0",
      borderRadius: "0",
      background: "transparent",
      touchAction: "none",
    });
    group.append(target);
    this.targets.set(key, target);
    return target;
  }
  update(dragging = false): void {
    this.controls.hidden = dragging;
    if (this.active) {
      if (
        this.dateGesture?.ready &&
        this.host.current().layout?.id !== this.dateGesture.layout
      )
        this.cancel();
      return;
    }
    const now = this.host.current(),
      seen = new Set<string>(),
      groups = new Set<string>();
    if (now.layout && !this.viewport.hidden && !now.disabled) {
      for (const [layer, object] of now.layout.objects.entries()) {
        const view = object.slicer,
          timeline = object.timeline;
        if (!view && !timeline) continue;
        groups.add(object.id);
        const group = this.group(object.id),
          mode = () => `${this.host.current().query.sheet}:${object.id}`;
        group.setAttribute("role", "group");
        group.setAttribute(
          "aria-label",
          timeline ? timeline.label : `Slicer ${view?.caption || view?.name}`,
        );
        const place = (
          key: string,
          regions: XlsxSlicerView["clear"],
          label: string,
          click?: (event: MouseEvent) => void,
          pressed?: boolean,
          disabled = false,
        ) => {
          for (const [band, region] of regions.entries()) {
            const full = `${object.id}:${key}:${band}`,
              target = this.target(full, group, !!click, click);
            if (
              timeline &&
              (key.startsWith("period:") || key.startsWith("endpoint:")) &&
              target instanceof HTMLButtonElement
            ) {
              const endpoint = timeline.handles.find(
                (item) => key === `endpoint:${item.handle}:${item.index}`,
              );
              this.dateTarget(
                full,
                target,
                object.id,
                endpoint?.index ?? Number(key.slice(7)),
                endpoint?.handle ?? 0,
              );
              if (endpoint) {
                if (!target.dataset.timelineEndpoint)
                  target.addEventListener("keydown", (event) => {
                    if (
                      ![
                        "ArrowLeft",
                        "ArrowRight",
                        "ArrowUp",
                        "ArrowDown",
                        "PageUp",
                        "PageDown",
                        "Home",
                        "End",
                      ].includes(event.key)
                    )
                      return;
                    event.preventDefault();
                    event.stopPropagation();
                    if (!this.active && !this.host.current().disabled)
                      this.stepEndpoint(object.id, endpoint.handle, event.key);
                  });
                target.dataset.timelineEndpoint = String(endpoint.handle);
                target.setAttribute("role", "slider");
                target.setAttribute(
                  "aria-valuemin",
                  String(timeline.navigation.minimum),
                );
                target.setAttribute(
                  "aria-valuemax",
                  String(timeline.navigation.maximum),
                );
                target.setAttribute("aria-valuenow", String(endpoint.index));
                target.setAttribute("aria-valuetext", endpoint.value);
              }
            }
            seen.add(full);
            Object.assign(target.style, {
              left: `${region.clip.x * now.scale}px`,
              top: `${region.clip.y * now.scale}px`,
              width: `${region.clip.width * now.scale}px`,
              height: `${region.clip.height * now.scale}px`,
              zIndex: String(layer + 4),
              cursor: key.startsWith("endpoint:")
                ? "ew-resize"
                : click
                  ? "pointer"
                  : "default",
            });
            if (target instanceof HTMLButtonElement) {
              target.setAttribute("aria-label", label);
              target.dataset.slicerMember = String(key.startsWith("member:"));
              target.tabIndex = band === 0 ? 0 : -1;
              target.setAttribute("aria-hidden", String(band > 0));
              target.title = label;
              if (pressed !== undefined)
                target.setAttribute("aria-pressed", String(pressed));
              target.disabled = disabled;
              target.style.background = key.startsWith("endpoint:")
                ? "#2563eb"
                : key === "multi" && pressed
                  ? "rgba(37, 99, 235, 0.15)"
                  : "transparent";
            }
          }
        };
        place("frame", object.regions, "");
        if (timeline) {
          const navigation = timeline.navigation;
          for (const [kind, regions] of [
            ["level", navigation.levelRegions],
            ["scroll", navigation.scrollRegions],
          ] as const)
            for (const [band, region] of regions.entries()) {
              const key = `${object.id}:view:${kind}:${band}${kind === "scroll" ? `:${navigation.level}` : ""}`;
              const target = this.navigationTarget(
                key,
                group,
                object.id,
                kind === "scroll" ? navigation.level : undefined,
              );
              seen.add(key);
              const { rect, clip } = region;
              Object.assign(target.style, {
                left: `${rect.x * now.scale}px`,
                top: `${rect.y * now.scale}px`,
                width: `${rect.width * now.scale}px`,
                height: `${rect.height * now.scale}px`,
                clipPath: `inset(${(clip.y - rect.y) * now.scale}px ${(rect.x + rect.width - clip.x - clip.width) * now.scale}px ${(rect.y + rect.height - clip.y - clip.height) * now.scale}px ${(clip.x - rect.x) * now.scale}px)`,
                zIndex: String(layer + 4),
                fontSize: `${11 * now.scale}px`,
              });
              target.tabIndex = band === 0 ? 0 : -1;
              target.setAttribute("aria-hidden", String(band > 0));
              if (target instanceof HTMLInputElement) {
                target.min = String(navigation.minimum);
                target.max = String(navigation.maximum);
                target.value = String(navigation.position);
                target.setAttribute("aria-valuetext", navigation.label);
                target.disabled = navigation.minimum === navigation.maximum;
              } else target.value = String(navigation.level);
            }
        }
        if (timeline) {
          for (const period of timeline.periods)
            place(
              `period:${period.index}`,
              period.regions,
              `Select timeline period ${period.label}`,
              (event) => {
                if (event.detail === 0)
                  this.selectDate(object.id, period.index);
              },
              period.selected,
            );
          for (const endpoint of timeline.handles)
            place(
              `endpoint:${endpoint.handle}:${endpoint.index}`,
              endpoint.regions,
              endpoint.handle === 1
                ? "Timeline start date"
                : "Timeline end date",
              () => {},
            );
        }
        if (!view) continue;
        for (const button of view.buttons)
          place(
            `member:${button.index}`,
            button.regions,
            `${button.label}${button.hasData ? "" : " (No data)"}`,
            (event) =>
              this.command(object.id, {
                kind: "select",
                index: button.index,
                additive:
                  event.ctrlKey || event.metaKey || this.multi.has(mode()),
              }),
            button.selected,
          );
        place("clear", view.clear, "Clear slicer filter", () =>
          this.command(object.id, {
            kind: "select",
            index: null,
            additive: false,
          }),
        );
        place(
          "multi",
          view.multi,
          "Multi-select slicer members",
          () => {
            if (this.multi.has(mode())) this.multi.delete(mode());
            else this.multi.add(mode());
            this.update();
          },
          this.multi.has(mode()),
        );
        place(
          "previous",
          view.previous,
          "Scroll slicer up",
          () => this.command(object.id, { kind: "scroll", rows: -1 }),
          undefined,
          view.start === 0,
        );
        place(
          "next",
          view.next,
          "Scroll slicer down",
          () => this.command(object.id, { kind: "scroll", rows: 1 }),
          undefined,
          view.start >= view.maximum,
        );
      }
    }
    for (const [key, target] of this.targets)
      if (!seen.has(key)) {
        const date = this.dateTargets.get(key);
        date?.pointer.cancel();
        date?.abort();
        this.dateTargets.delete(key);
        target.remove();
        this.targets.delete(key);
      }
    for (const [id, group] of this.groups)
      if (!groups.has(id)) {
        group.remove();
        this.groups.delete(id);
      }
  }
}
