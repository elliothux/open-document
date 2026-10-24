import type { XlsxClient } from "./xlsx.js";
import type { XlsxSlicerView } from "@open-document/wasm/xlsx";
import type { PointerHost } from "./spreadsheet-pointer.js";
import type { CanvasSurface } from "./canvas-surface.js";
import { SpreadsheetTimelinePointer } from "./spreadsheet-timeline-pointer.js";
import { SpreadsheetSlicerPointer } from "./spreadsheet-slicer-pointer.js";
import { stepTimelineEndpoint } from "./spreadsheet-timeline-endpoints.js";

type Intent =
  | { kind: "select"; index: number | null; additive: boolean }
  | { kind: "scroll"; offset: number }
  | { kind: "position"; position: number };

/** Native controls use core geometry and the existing worksheet command queue. */
export class SpreadsheetSlicers {
  private readonly controls = document.createElement("div");
  private readonly groups = new Map<string, HTMLDivElement>();
  private readonly targets = new Map<string, HTMLElement>();
  private readonly multi = new Set<string>();
  private readonly dates: SpreadsheetTimelinePointer;
  private readonly members: SpreadsheetSlicerPointer;
  private hovered: { target: HTMLButtonElement; sheet: string } | undefined;
  private hoverQueued = false;
  constructor(
    private readonly surface: CanvasSurface,
    holder: HTMLElement,
    private readonly viewport: HTMLElement,
    private readonly client: XlsxClient,
    private readonly signal: AbortSignal,
    private readonly host: PointerHost,
  ) {
    this.members = new SpreadsheetSlicerPointer(
      surface,
      viewport,
      client,
      signal,
      host,
    );
    this.dates = new SpreadsheetTimelinePointer(
      surface,
      viewport,
      client,
      signal,
      host,
    );
    holder.append(this.controls);
    const hover = (event: PointerEvent) => {
      const target = event.target;
      this.setHover(
        event.buttons === 0 &&
          event.pointerType !== "touch" &&
          target instanceof HTMLButtonElement &&
          target.dataset.slicerIndex !== undefined
          ? target
          : undefined,
      );
    };
    this.controls.addEventListener("pointerover", hover);
    this.controls.addEventListener("pointermove", hover);
    this.controls.addEventListener("pointerout", (event) => {
      if (event.target === this.hovered?.target) this.setHover(undefined);
    });
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
    return this.dates.active || this.members.active;
  }
  get hover(): { object: string; index: number } | undefined {
    const now = this.host.current(),
      hovered = this.hovered;
    if (
      !hovered ||
      this.active ||
      now.disabled ||
      this.controls.hidden ||
      hovered.sheet !== now.query.sheet ||
      !hovered.target.isConnected
    )
      return undefined;
    const object = hovered.target.dataset.slicerObject;
    return object === undefined
      ? undefined
      : {
          object,
          index: Number(hovered.target.dataset.slicerIndex),
        };
  }
  private setHover(target: HTMLButtonElement | undefined): void {
    if (target === this.hovered?.target) return;
    const now = this.host.current();
    this.hovered = target ? { target, sheet: now.query.sheet } : undefined;
    if (this.hoverQueued || this.signal.aborted || this.active || now.disabled)
      return;
    this.hoverQueued = true;
    void this.host
      .run(async () => {
        this.hoverQueued = false;
        if (
          !this.signal.aborted &&
          !this.active &&
          !this.host.current().disabled
        )
          await this.host.render(true);
      }, true)
      .catch((error: unknown) => {
        if (!this.signal.aborted) this.host.report(error);
      });
  }
  cancel(): void {
    this.setHover(undefined);
    this.dates.cancel();
    this.members.cancel();
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
        const object = layout?.objects.find((item) => item.id === id);
        if (!layout || (!object?.slicer && !object?.timeline)) return;
        if (object.timeline && intent.kind !== "scroll") return;
        const view = object.slicer;
        if (intent.kind === "position" && !view) return;
        this.host.assign(
          await this.client.editSheet(
            now.query.revision,
            sheet,
            object.timeline && intent.kind === "scroll"
              ? {
                  action: "scrollTimeline",
                  name: object.timeline.name,
                  level: object.timeline.navigation.level,
                  position: Math.max(
                    object.timeline.navigation.minimum,
                    Math.min(
                      object.timeline.navigation.maximum,
                      object.timeline.navigation.position + intent.offset,
                    ),
                  ),
                }
              : intent.kind === "scroll" || intent.kind === "position"
                ? {
                    action: "scrollSlicer",
                    layout: layout.id,
                    id,
                    position: Math.max(
                      0,
                      Math.min(
                        view?.maximum ?? 0,
                        intent.kind === "position"
                          ? intent.position
                          : (view?.start ?? 0) + intent.offset,
                      ),
                    ),
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
            ((focused instanceof HTMLButtonElement ||
              focused instanceof HTMLInputElement) &&
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
  private slicerScrollTarget(
    key: string,
    group: HTMLElement,
    object: string,
  ): HTMLInputElement {
    const known = this.targets.get(key);
    if (known instanceof HTMLInputElement) return known;
    const target = document.createElement("input");
    target.type = "range";
    target.step = "1";
    target.min = "0";
    target.setAttribute("aria-label", "Slicer scroll position");
    target.setAttribute("aria-orientation", "vertical");
    Object.assign(target.style, {
      position: "absolute",
      padding: "0",
      margin: "0",
      border: "0",
      writingMode: "vertical-lr",
      direction: "ltr",
      touchAction: "none",
    });
    target.addEventListener("input", () =>
      this.command(object, {
        kind: "position",
        position: Number(target.value),
      }),
    );
    group.append(target);
    this.targets.set(key, target);
    return target;
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
      } else if (!view || event.target instanceof HTMLInputElement) return;
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
        this.command(id, { kind: "scroll", offset: rows });
      }
    });
    group.addEventListener(
      "wheel",
      (event) => {
        const object = this.host
          .current()
          .layout?.objects.find((object) => object.id === id);
        const delta = object?.timeline
          ? Math.abs(event.deltaX) > Math.abs(event.deltaY)
            ? event.deltaX
            : event.deltaY
          : event.deltaY;
        if (
          !delta ||
          (object?.timeline
            ? event.ctrlKey || !object.timeline.navigation.scrollRegions.length
            : !object?.slicer || object.slicer.maximum === 0)
        )
          return;
        event.preventDefault();
        event.stopPropagation();
        this.cancel();
        this.command(id, { kind: "scroll", offset: delta > 0 ? 1 : -1 });
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
      this.dates.checkLayout();
      this.members.checkLayout();
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
              view &&
              key.startsWith("member:") &&
              target instanceof HTMLButtonElement
            ) {
              target.dataset.slicerObject = object.id;
              target.dataset.slicerIndex = key.slice(7);
              this.members.bind(
                full,
                target,
                object.id,
                Number(key.slice(7)),
                () => this.multi.has(mode()),
              );
            }
            if (
              timeline &&
              (key.startsWith("period:") || key.startsWith("endpoint:")) &&
              target instanceof HTMLButtonElement
            ) {
              const endpoint = timeline.handles.find(
                (item) => key === `endpoint:${item.handle}:${item.index}`,
              );
              this.dates.bind(
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
                  this.dates.select(object.id, period.index);
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
        for (const [band, region] of view.scroll.entries()) {
          const key = `${object.id}:scroll:${band}`,
            target = this.slicerScrollTarget(key, group, object.id),
            { rect, clip } = region;
          seen.add(key);
          Object.assign(target.style, {
            left: `${rect.x * now.scale}px`,
            top: `${rect.y * now.scale}px`,
            width: `${rect.width * now.scale}px`,
            height: `${rect.height * now.scale}px`,
            clipPath: `inset(${(clip.y - rect.y) * now.scale}px ${(rect.x + rect.width - clip.x - clip.width) * now.scale}px ${(rect.y + rect.height - clip.y - clip.height) * now.scale}px ${(clip.x - rect.x) * now.scale}px)`,
            zIndex: String(layer + 4),
          });
          target.max = String(view.maximum);
          target.value = String(view.start);
          target.disabled = view.maximum === 0;
          target.tabIndex = band === 0 ? 0 : -1;
          target.setAttribute("aria-hidden", String(band > 0));
          target.setAttribute(
            "aria-valuetext",
            `Row ${view.start + 1} of ${view.maximum + view.page}`,
          );
        }
        for (const button of view.buttons)
          place(
            `member:${button.index}`,
            button.regions,
            `${button.label}${button.hasData ? "" : " (No data)"}`,
            (event) => {
              if (event.detail === 0)
                this.command(object.id, {
                  kind: "select",
                  index: button.index,
                  additive:
                    event.ctrlKey || event.metaKey || this.multi.has(mode()),
                });
            },
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
          () => this.command(object.id, { kind: "scroll", offset: -1 }),
          undefined,
          view.start === 0,
        );
        place(
          "next",
          view.next,
          "Scroll slicer down",
          () => this.command(object.id, { kind: "scroll", offset: 1 }),
          undefined,
          view.start >= view.maximum,
        );
      }
    }
    for (const [key, target] of this.targets)
      if (!seen.has(key)) {
        this.dates.remove(key);
        this.members.remove(key);
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
