import type { PdfImageCrop } from "../core/pdf.js";

/** Appearance-only crop percentages; original image pixels remain in the PDF. */
export class PdfImageCropInputs {
  readonly element = document.createElement("fieldset");
  readonly inputs = {
    x: document.createElement("input"),
    y: document.createElement("input"),
    width: document.createElement("input"),
    height: document.createElement("input"),
  };
  private readonly events = new AbortController();
  private readonly legend = document.createElement("legend");
  constructor(change: () => void) {
    this.element.append(this.legend);
    for (const input of Object.values(this.inputs)) {
      input.type = "number";
      input.min = "0";
      input.max = "100";
      input.step = "0.1";
      const label = document.createElement("label"),
        caption = document.createElement("span");
      label.append(caption, input);
      this.element.append(label);
    }
    this.element.addEventListener("input", change, {
      signal: this.events.signal,
    });
    this.element.addEventListener("change", change, {
      signal: this.events.signal,
    });
    this.setLocale("en-US");
    this.reset();
    this.show(false, false);
  }
  setLocale(locale: "zh-CN" | "en-US"): void {
    this.legend.textContent =
      locale === "zh-CN"
        ? "外观裁剪：保留原图数据，不用于脱敏"
        : "Appearance crop: retains original data; not redaction";
    const labels =
      locale === "zh-CN"
        ? {
            x: "裁剪左侧 (%)",
            y: "裁剪顶部 (%)",
            width: "保留宽度 (%)",
            height: "保留高度 (%)",
          }
        : {
            x: "Crop left (%)",
            y: "Crop top (%)",
            width: "Retained width (%)",
            height: "Retained height (%)",
          };
    for (const [key, input] of Object.entries(this.inputs)) {
      const text = labels[key as keyof typeof labels];
      input.setAttribute("aria-label", text);
      const caption = input.parentElement?.querySelector("span");
      if (caption) caption.textContent = text;
    }
  }
  reset(): void {
    this.inputs.x.value = this.inputs.y.value = "0";
    this.inputs.width.value = this.inputs.height.value = "100";
  }
  get signature(): string {
    return JSON.stringify(
      Object.values(this.inputs).map((input) => input.value),
    );
  }
  read(): PdfImageCrop {
    return {
      x: Number(this.inputs.x.value) / 100,
      y: Number(this.inputs.y.value) / 100,
      width: Number(this.inputs.width.value) / 100,
      height: Number(this.inputs.height.value) / 100,
    };
  }
  show(visible: boolean, disabled: boolean): void {
    this.element.hidden = !visible;
    for (const input of Object.values(this.inputs)) input.disabled = disabled;
  }
  dispose(): void {
    this.events.abort();
  }
}
