import type {
  PdfFieldDesign,
  PdfFieldWidgetDesign,
  PdfPage,
} from "../core/pdf.js";

interface WidgetRow {
  original: PdfFieldWidgetDesign;
  element: HTMLFieldSetElement;
  page: HTMLSelectElement;
  inputs: Record<
    | "x"
    | "y"
    | "width"
    | "height"
    | "border"
    | "borderColor"
    | "background"
    | "exportValue",
    HTMLInputElement
  >;
}

/** Native widget controls participate in the editor's existing draft barrier. */
export class PdfFieldWidgetInputs {
  readonly element = document.createElement("div");
  private pages: readonly PdfPage[] = [];
  private rows: WidgetRow[] = [];
  private locale: "en-US" | "zh-CN" = "en-US";
  private readonly events = new AbortController();

  constructor(change: () => void) {
    this.element.addEventListener("input", change, {
      signal: this.events.signal,
    });
    this.element.addEventListener("change", change, {
      signal: this.events.signal,
    });
  }
  setPages(pages: readonly PdfPage[]): void {
    this.pages = pages;
    for (const row of this.rows) this.pageOptions(row);
  }
  setLocale(locale: "en-US" | "zh-CN"): void {
    if (locale === this.locale) return;
    this.locale = locale;
    for (const [index, row] of this.rows.entries()) {
      const prefix = `${locale === "zh-CN" ? "控件" : "Widget"} ${index + 1}`;
      const legend = row.element.querySelector("legend");
      if (legend) legend.textContent = prefix;
      const pageLabel = locale === "zh-CN" ? "所在页" : "Page";
      row.page.setAttribute("aria-label", `${prefix} ${pageLabel}`);
      const pageCaption = row.page.parentElement?.querySelector("span");
      if (pageCaption) pageCaption.textContent = pageLabel;
      for (const [key, input] of Object.entries(row.inputs)) {
        const labels =
          locale === "zh-CN"
            ? {
                x: "横向位置",
                y: "纵向位置",
                width: "宽度",
                height: "高度",
                border: "边框宽度",
                borderColor: "边框颜色",
                background: "背景色（留空透明）",
                exportValue: "单选导出值",
              }
            : {
                x: "Horizontal position",
                y: "Vertical position",
                width: "Width",
                height: "Height",
                border: "Border width",
                borderColor: "Border color",
                background: "Background (empty for transparent)",
                exportValue: "Radio export value",
              };
        const label = labels[key as keyof typeof labels];
        input.setAttribute("aria-label", `${prefix} ${label}`);
        const caption = input.parentElement?.querySelector("span");
        if (caption) caption.textContent = label;
      }
      this.pageOptions(row);
    }
  }
  set(
    widgets: readonly PdfFieldWidgetDesign[],
    kind: PdfFieldDesign["kind"] = "text",
  ): void {
    this.rows = widgets.map((widget, index) => {
      const element = document.createElement("fieldset");
      const legend = document.createElement("legend");
      const prefix = `${this.locale === "zh-CN" ? "控件" : "Widget"} ${index + 1}`;
      legend.textContent = prefix;
      element.append(legend);
      const page = document.createElement("select");
      const pageLabel = document.createElement("label"),
        caption = document.createElement("span");
      const pageText = this.locale === "zh-CN" ? "所在页" : "Page";
      caption.textContent = pageText;
      page.setAttribute("aria-label", `${prefix} ${pageText}`);
      pageLabel.append(caption, page);
      element.append(pageLabel);
      const inputs = {
        x: document.createElement("input"),
        y: document.createElement("input"),
        width: document.createElement("input"),
        height: document.createElement("input"),
        border: document.createElement("input"),
        borderColor: document.createElement("input"),
        background: document.createElement("input"),
        exportValue: document.createElement("input"),
      };
      const labels =
        this.locale === "zh-CN"
          ? {
              x: "横向位置",
              y: "纵向位置",
              width: "宽度",
              height: "高度",
              border: "边框宽度",
              borderColor: "边框颜色",
              background: "背景色（留空透明）",
              exportValue: "单选导出值",
            }
          : {
              x: "Horizontal position",
              y: "Vertical position",
              width: "Width",
              height: "Height",
              border: "Border width",
              borderColor: "Border color",
              background: "Background (empty for transparent)",
              exportValue: "Radio export value",
            };
      for (const [key, input] of Object.entries(inputs)) {
        const label = document.createElement("label"),
          caption = document.createElement("span");
        const numeric = ["x", "y", "width", "height", "border"].includes(key);
        input.type = numeric ? "number" : "text";
        if (numeric) {
          input.step = "0.01";
          input.min = key === "width" || key === "height" ? "0.01" : "0";
        }
        const text = labels[key as keyof typeof labels];
        caption.textContent = text;
        input.setAttribute("aria-label", `${prefix} ${text}`);
        label.append(caption, input);
        element.append(label);
        if (key === "exportValue") label.hidden = kind !== "radio";
      }
      inputs.x.value = String(widget.placement.x);
      inputs.y.value = String(widget.placement.y);
      inputs.width.value = String(widget.placement.width);
      inputs.height.value = String(widget.placement.height);
      inputs.border.value = String(widget.border);
      inputs.borderColor.value = widget.borderColor;
      inputs.background.value = widget.background;
      inputs.exportValue.value = widget.exportValue;
      const row: WidgetRow = { original: widget, element, page, inputs };
      this.pageOptions(row);
      return row;
    });
    this.element.replaceChildren(...this.rows.map((row) => row.element));
  }
  private pageOptions(row: WidgetRow): void {
    const selected = row.page.value || row.original.page;
    const options = this.pages.map(
      (page, index) =>
        new Option(
          this.locale === "zh-CN" ? `第 ${index + 1} 页` : `Page ${index + 1}`,
          page.id,
        ),
    );
    if (!options.some((option) => option.value === selected))
      options.push(
        new Option(
          this.locale === "zh-CN" ? "原所在页" : "Original page",
          selected,
        ),
      );
    row.page.replaceChildren(...options);
    row.page.value = selected;
  }
  get signature(): string {
    return JSON.stringify(
      this.rows.map((row) => [
        row.original.id,
        row.page.value,
        ...Object.values(row.inputs).map((input) => input.value),
      ]),
    );
  }
  read(): PdfFieldWidgetDesign[] {
    return this.rows.map((row) => ({
      id: row.original.id,
      page: row.page.value,
      placement: {
        x: Number(row.inputs.x.value),
        y: Number(row.inputs.y.value),
        width: Number(row.inputs.width.value),
        height: Number(row.inputs.height.value),
        rotation: 0,
      },
      border: Number(row.inputs.border.value),
      borderColor: row.inputs.borderColor.value,
      background: row.inputs.background.value,
      exportValue: row.inputs.exportValue.value,
    }));
  }
  show(visible: boolean, disabled: boolean): void {
    this.element.hidden = !visible;
    for (const row of this.rows) {
      row.page.disabled = disabled;
      for (const input of Object.values(row.inputs)) input.disabled = disabled;
    }
  }
  dispose(): void {
    this.events.abort();
    this.rows = [];
    this.pages = [];
    this.element.replaceChildren();
  }
}
