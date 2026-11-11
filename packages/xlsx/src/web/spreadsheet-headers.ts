import type { XlsxSheetEdit } from "../core/xlsx.js";
import type { PointerHost } from "./spreadsheet-pointer.js";
import type { XlsxClient } from "./xlsx.js";

type Axis = "rows" | "columns";
type AxisAction = "insert" | "delete" | "fit" | "size";

interface Header {
  readonly axis: Axis;
  readonly index: number;
  readonly button: HTMLButtonElement;
}

interface AxisTarget extends Header {
  readonly sheet: string;
  readonly revision: number;
}

function headerLabels(axis: Axis, name: string, zh: boolean) {
  const row = axis === "rows";
  if (zh)
    return {
      name: row ? `第 ${name} 行` : `${name} 列`,
      insert: row ? "在上方插入行" : "在前方插入列",
      delete: row ? "删除行" : "删除列",
      fit: row ? "自动调整行高" : "自动调整列宽",
      size: row ? "设置行高" : "设置列宽",
      dimension: row ? "行高（点）" : "列宽（字符）",
      apply: "应用",
      cancel: "取消",
    };
  return {
    name: row ? `Row ${name}` : `Column ${name}`,
    insert: row ? "Insert row above" : "Insert column before",
    delete: row ? "Delete row" : "Delete column",
    fit: row ? "Auto-fit row height" : "Auto-fit column width",
    size: row ? "Set row height" : "Set column width",
    dimension: row ? "Row height (points)" : "Column width (characters)",
    apply: "Apply",
    cancel: "Cancel",
  };
}

/** Header controls project core geometry and send the ordinary worksheet commands. */
export class SpreadsheetHeaders {
  private readonly layer = document.createElement("div");
  private readonly menu = document.createElement("div");
  private readonly dialog = document.createElement("dialog");
  private readonly value = document.createElement("input");
  private readonly caption = document.createElement("label");
  private readonly heading = document.createElement("h2");
  private readonly applySize = document.createElement("button");
  private readonly cancelSize = document.createElement("button");
  private readonly headers = new Map<string, Header>();
  private target: AxisTarget | undefined;
  private openVersion = 0;

  constructor(
    private readonly holder: HTMLElement,
    private readonly client: XlsxClient,
    private readonly host: PointerHost,
    private readonly signal: AbortSignal,
  ) {
    this.layer.className = "od-xlsx-axis-layer";
    this.menu.className = "od-menu od-xlsx-axis-menu";
    this.menu.popover = "auto";
    this.menu.tabIndex = -1;
    this.menu.setAttribute("role", "menu");
    this.dialog.className = "od-xlsx-axis-dialog";
    this.value.type = "number";
    this.value.required = true;
    this.value.min = "0";
    this.value.step = "any";
    this.applySize.type = "submit";
    this.cancelSize.type = "button";
    const form = document.createElement("form");
    this.caption.append(this.value);
    form.append(this.heading, this.caption, this.applySize, this.cancelSize);
    this.dialog.append(form);
    holder.append(this.layer, this.menu, this.dialog);

    const options = { signal };
    window.addEventListener("scroll", () => this.positionMenu(), {
      ...options,
      capture: true,
      passive: true,
    });
    this.layer.addEventListener(
      "pointerdown",
      (event) => {
        if (this.header(event.target)) event.preventDefault();
      },
      options,
    );
    this.layer.addEventListener(
      "click",
      (event) => this.openFrom(event),
      options,
    );
    this.layer.addEventListener(
      "contextmenu",
      (event) => this.openFrom(event),
      options,
    );
    this.layer.addEventListener(
      "keydown",
      (event) => this.headerKey(event),
      options,
    );
    this.menu.addEventListener(
      "keydown",
      (event) => this.menuKey(event),
      options,
    );
    this.dialog.addEventListener(
      "keydown",
      (event) => event.stopPropagation(),
      options,
    );
    this.menu.addEventListener(
      "toggle",
      () => {
        this.target?.button.setAttribute(
          "aria-expanded",
          String(this.menu.matches(":popover-open")),
        );
      },
      options,
    );
    this.cancelSize.addEventListener(
      "click",
      () => this.dialog.close(),
      options,
    );
    this.dialog.addEventListener(
      "close",
      () => this.target?.button.focus({ preventScroll: true }),
      options,
    );
    form.addEventListener(
      "submit",
      (event) => {
        event.preventDefault();
        if (this.target && this.value.checkValidity())
          this.execute(this.target, "size", this.value.valueAsNumber);
      },
      options,
    );
    const locale = holder.closest<HTMLElement>("[lang]");
    if (locale) {
      const refreshLabels = new MutationObserver(() => this.update());
      refreshLabels.observe(locale, {
        attributes: true,
        attributeFilter: ["lang"],
      });
      signal.addEventListener("abort", () => refreshLabels.disconnect(), {
        once: true,
      });
    }
    signal.addEventListener(
      "abort",
      () => {
        this.target = undefined;
        this.layer.remove();
        this.menu.remove();
        this.dialog.remove();
      },
      { once: true },
    );
  }

  update(): void {
    if (this.signal.aborted) return;
    const { layout, scale, query, disabled } = this.host.current();
    const visible =
      layout &&
      !this.holder.parentElement?.hidden &&
      !this.client.readOnly &&
      !disabled;
    if (
      this.target &&
      (!visible ||
        query.sheet !== this.target.sheet ||
        query.revision !== this.target.revision)
    )
      this.dismiss();
    this.layer.hidden = !visible;
    if (!layout) return;
    const seen = new Set<string>();
    const zh = this.layer.closest("[lang]")?.getAttribute("lang") === "zh-CN";
    for (const axis of ["rows", "columns"] as const) {
      let first = true;
      for (const item of layout[axis]) {
        const { clip } = item;
        if (clip.width <= 0 || clip.height <= 0) continue;
        const key = `${axis}:${item.index}`;
        const { button } =
          this.headers.get(key) ?? this.makeHeader(key, axis, item.index);
        const label = headerLabels(axis, item.label, zh).name;
        seen.add(key);
        button.tabIndex = first ? 0 : -1;
        first = false;
        button.setAttribute("aria-label", label);
        button.dataset.headerName = item.label;
        Object.assign(button.style, {
          left: `${clip.x * scale}px`,
          top: `${clip.y * scale}px`,
          width: `${clip.width * scale}px`,
          height: `${clip.height * scale}px`,
        });
      }
    }
    for (const [key, header] of this.headers) {
      if (seen.has(key)) continue;
      if (this.target?.button === header.button) this.dismiss();
      header.button.remove();
      this.headers.delete(key);
    }
    this.positionMenu();
  }

  private makeHeader(key: string, axis: Axis, index: number): Header {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "od-xlsx-axis-button";
    button.dataset.axisHeader = key;
    button.setAttribute("aria-haspopup", "menu");
    button.setAttribute("aria-expanded", "false");
    this.layer.append(button);
    const header = { axis, index, button };
    this.headers.set(key, header);
    return header;
  }

  private header(target: EventTarget | null): Header | undefined {
    return target instanceof HTMLElement
      ? this.headers.get(target.dataset.axisHeader ?? "")
      : undefined;
  }

  private headerKey(event: KeyboardEvent): void {
    const from = this.header(event.target);
    if (!from) return;
    if (
      event.key === "ContextMenu" ||
      (event.shiftKey && event.key === "F10")
    ) {
      this.openFrom(event);
      return;
    }
    const rows = from.axis === "rows";
    const step =
      event.key === (rows ? "ArrowUp" : "ArrowLeft")
        ? -1
        : event.key === (rows ? "ArrowDown" : "ArrowRight")
          ? 1
          : 0;
    if (!step && event.key !== "Home" && event.key !== "End") return;
    event.preventDefault();
    const buttons = [...this.headers.values()]
      .filter((header) => header.axis === from.axis)
      .map((header) => header.button)
      .sort((a, b) =>
        rows ? a.offsetTop - b.offsetTop : a.offsetLeft - b.offsetLeft,
      );
    const index =
      event.key === "Home"
        ? 0
        : event.key === "End"
          ? buttons.length - 1
          : buttons.indexOf(from.button) + step;
    if (buttons[index]) {
      for (const button of buttons)
        button.tabIndex = button === buttons[index] ? 0 : -1;
      buttons[index].focus({ preventScroll: true });
    }
  }

  private openFrom(event: Event): void {
    const header = this.header(event.target);
    if (!header || this.client.readOnly || this.host.current().disabled) return;
    event.preventDefault();
    event.stopPropagation();
    const version = ++this.openVersion;
    const sheet = this.host.current().query.sheet;
    void this.host
      .run(async () => {
        await this.host.prepare();
        const { query, disabled } = this.host.current();
        if (
          version !== this.openVersion ||
          sheet !== query.sheet ||
          !header.button.isConnected ||
          this.layer.hidden ||
          this.client.readOnly ||
          disabled ||
          this.signal.aborted
        )
          return;
        this.show({ ...header, sheet, revision: query.revision });
      })
      .catch((error: unknown) => this.host.report(error));
  }

  private show(target: AxisTarget): void {
    const query = this.host.current().query;
    const labels = this.labels(target);
    const protectedReason = query.dimensions.readOnlyReason;
    this.target?.button.setAttribute("aria-expanded", "false");
    this.target = target;
    this.menu.setAttribute("aria-label", labels.name);
    const items = (["insert", "delete", "fit", "size"] as const).map(
      (action) => {
        const button = document.createElement("button");
        const reason =
          protectedReason ||
          (action === "insert" || action === "delete"
            ? query.sheetEditReason
            : "");
        button.type = "button";
        button.setAttribute("role", "menuitem");
        button.textContent = labels[action];
        button.disabled = !!reason;
        button.title = reason;
        button.addEventListener("click", () => {
          if (action === "size") this.showSize(target);
          else this.execute(target, action);
        });
        return button;
      },
    );
    const caption = document.createElement("span");
    caption.className = "od-xlsx-axis-caption";
    caption.textContent = labels.name;
    this.menu.replaceChildren(caption, ...items);
    if (protectedReason) {
      const note = document.createElement("p");
      note.textContent = protectedReason;
      this.menu.append(note);
    }
    this.menu.style.left = "0";
    this.menu.style.top = "0";
    if (!this.menu.matches(":popover-open")) this.menu.showPopover();
    this.positionMenu();
    (items.find((item) => !item.disabled) ?? this.menu).focus({
      preventScroll: true,
    });
  }

  private positionMenu(): void {
    if (!this.target || !this.menu.matches(":popover-open")) return;
    const rect = this.target.button.getBoundingClientRect();
    const { clientWidth: width, clientHeight: height } =
      document.documentElement;
    if (
      rect.bottom <= 0 ||
      rect.top >= height ||
      rect.right <= 0 ||
      rect.left >= width
    ) {
      this.dismiss();
      return;
    }
    this.menu.style.left = `${Math.max(8, Math.min(rect.left, width - this.menu.offsetWidth - 8))}px`;
    this.menu.style.top = `${Math.max(8, Math.min(rect.bottom + 2, height - this.menu.offsetHeight - 8))}px`;
  }

  private labels(target: AxisTarget) {
    const zh = this.layer.closest("[lang]")?.getAttribute("lang") === "zh-CN";
    return headerLabels(
      target.axis,
      target.button.dataset.headerName ?? String(target.index),
      zh,
    );
  }

  private menuKey(event: KeyboardEvent): void {
    event.stopPropagation();
    if (event.key === "Escape") {
      event.preventDefault();
      const button = this.target?.button;
      this.dismiss();
      button?.focus({ preventScroll: true });
      return;
    }
    if (!["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const items = Array.from(
      this.menu.querySelectorAll<HTMLButtonElement>("button:enabled"),
    );
    const index = items.findIndex((item) => item === event.target);
    const next =
      event.key === "Home"
        ? 0
        : event.key === "End"
          ? items.length - 1
          : (index + (event.key === "ArrowDown" ? 1 : items.length - 1)) %
            items.length;
    items[next]?.focus();
  }

  private showSize(target: AxisTarget): void {
    this.menu.hidePopover();
    const labels = this.labels(target);
    this.heading.textContent = labels.name;
    this.dialog.setAttribute("aria-label", labels.size);
    this.caption.replaceChildren(labels.dimension, this.value);
    this.value.value = "";
    this.value.max = target.axis === "rows" ? "409.5" : "255";
    this.applySize.textContent = labels.apply;
    this.cancelSize.textContent = labels.cancel;
    this.dialog.showModal();
    this.value.focus();
  }

  private dismiss(): void {
    this.target?.button.setAttribute("aria-expanded", "false");
    this.target = undefined;
    if (this.menu.matches(":popover-open")) this.menu.hidePopover();
    if (this.dialog.open) this.dialog.close();
  }

  private execute(target: AxisTarget, action: AxisAction, size = 0): void {
    this.dismiss();
    const { axis, index, sheet, revision } = target;
    const row = axis === "rows";
    void this.host
      .run(async () => {
        const { query, profile } = this.host.current();
        if (query.sheet !== sheet || query.revision !== revision)
          throw new Error("Worksheet header target changed");
        if (action === "fit") {
          this.host.assign(
            await this.client.execute({
              operation: "autoFitXlsx",
              revision,
              sheet,
              first: index,
              last: index,
              axis,
              profile,
            }),
          );
        } else {
          const change: XlsxSheetEdit =
            action === "size"
              ? {
                  action: row ? "rowHeight" : "columnWidth",
                  first: index,
                  last: index,
                  size,
                }
              : {
                  action:
                    action === "insert"
                      ? row
                        ? "insertRows"
                        : "insertColumns"
                      : row
                        ? "deleteRows"
                        : "deleteColumns",
                  first: index,
                  count: 1,
                };
          this.host.assign(
            await this.client.execute({
              operation: "editXlsxSheet",
              revision,
              sheet,
              change,
            }),
          );
        }
        await this.host.render();
        this.host.focus();
      })
      .catch((error: unknown) => this.host.report(error));
  }
}
