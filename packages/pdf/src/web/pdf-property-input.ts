import { PdfObjectInputs } from "./pdf-object-input.js";
import { PdfFieldInputs } from "./pdf-field-input.js";
import { PdfInkInputs } from "./pdf-annotation-input.js";
import { PdfFieldWidgetInputs } from "./pdf-field-edit.js";
import { PdfImageCropInputs } from "./pdf-image-crop.js";

/** DOM controls and events only; the editor owns all drafts and document state. */
export class PdfPropertyInputs {
  readonly element = document.createElement("div");
  readonly text = document.createElement("textarea");
  readonly checked = document.createElement("input");
  readonly fieldChoice = document.createElement("select");
  readonly x = document.createElement("input");
  readonly y = document.createElement("input");
  readonly objectInputs: PdfObjectInputs;
  readonly fieldInputs: PdfFieldInputs;
  readonly inkInputs: PdfInkInputs;
  readonly widgetInputs: PdfFieldWidgetInputs;
  readonly cropInputs: PdfImageCropInputs;
  private readonly events = new AbortController();
  private readonly emit: () => void;

  constructor(change: () => void, composition: (active: boolean) => void) {
    const signal = this.events.signal;
    this.emit = () => {
      if (!signal.aborted) change();
    };
    this.objectInputs = new PdfObjectInputs(this.emit);
    this.fieldInputs = new PdfFieldInputs(this.emit);
    this.inkInputs = new PdfInkInputs(
      this.emit,
      () => this.objectInputs.read("").placement,
    );
    this.widgetInputs = new PdfFieldWidgetInputs(this.emit);
    this.cropInputs = new PdfImageCropInputs(this.emit);
    this.text.setAttribute("aria-label", "PDF property text");
    this.text.maxLength = 32767;
    this.checked.type = "checkbox";
    this.checked.setAttribute("aria-label", "PDF checkbox value");
    this.fieldChoice.setAttribute("aria-label", "PDF choice value");
    for (const [input, label] of [
      [this.x, "Note horizontal position"],
      [this.y, "Note vertical position"],
    ] as const) {
      input.type = "number";
      input.value = "20";
      input.min = "0";
      input.setAttribute("aria-label", label);
    }
    this.element.addEventListener("compositionstart", () => composition(true), {
      signal,
    });
    this.element.addEventListener("compositionend", () => composition(false), {
      signal,
    });
    for (const [key, input] of [
      ["text", this.text],
      ["checked", this.checked],
      ["choice", this.fieldChoice],
      ["x", this.x],
      ["y", this.y],
    ] as const) {
      const label = document.createElement("label"),
        caption = document.createElement("span");
      label.dataset.pdfControl = key;
      caption.textContent = input.getAttribute("aria-label");
      label.append(caption, input);
      this.element.append(label);
      input.addEventListener("input", this.emit, { signal });
      input.addEventListener("change", this.emit, { signal });
    }
    this.element.append(
      this.objectInputs.element,
      this.fieldInputs.element,
      this.inkInputs.element,
      this.widgetInputs.element,
      this.cropInputs.element,
    );
    this.inkInputs.show(false, false);
    this.widgetInputs.show(false, false);
  }

  dispose(): void {
    this.events.abort();
    this.inkInputs.dispose();
    this.widgetInputs.dispose();
    this.cropInputs.dispose();
    for (const element of [
      this.objectInputs.element,
      this.fieldInputs.element,
      this.inkInputs.element,
      this.widgetInputs.element,
      this.cropInputs.element,
    ]) {
      element.removeEventListener("input", this.emit);
      element.removeEventListener("change", this.emit);
    }
  }
}
