import type { XlsxClient } from "./xlsx.js";
import type { XlsxSlicerView } from "@open-document/wasm/xlsx";
import type { PointerHost } from "./spreadsheet-pointer.js";

type Intent =
  | { kind: "select"; index: number | null; additive: boolean }
  | { kind: "scroll"; rows: number };

/** Native controls use core geometry and the existing worksheet command queue. */
export class SpreadsheetSlicers {
  private readonly controls = document.createElement("div");
  private readonly groups = new Map<string, HTMLDivElement>();
  private readonly targets = new Map<string, HTMLElement>();
  private readonly multi = new Set<string>();
  constructor(
    holder: HTMLElement,
    private readonly viewport: HTMLElement,
    private readonly client: XlsxClient,
    private readonly signal: AbortSignal,
    private readonly host: PointerHost,
  ) {
    holder.append(this.controls);
    signal.addEventListener("abort", () => this.controls.remove(), {
      once: true,
    });
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
      if (!view) return;
      if (event.key === "Escape") {
        event.preventDefault();
        this.host.focus();
      } else if (
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
        group.setAttribute("role", timeline ? "img" : "group");
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
            seen.add(full);
            Object.assign(target.style, {
              left: `${region.clip.x * now.scale}px`,
              top: `${region.clip.y * now.scale}px`,
              width: `${region.clip.width * now.scale}px`,
              height: `${region.clip.height * now.scale}px`,
              zIndex: String(layer + 4),
              cursor: click ? "pointer" : "default",
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
              target.style.background =
                key === "multi" && pressed
                  ? "rgba(37, 99, 235, 0.15)"
                  : "transparent";
            }
          }
        };
        place("frame", object.regions, "");
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
