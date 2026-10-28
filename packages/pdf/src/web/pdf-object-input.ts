import type { PdfTextSpec } from "../core/pdf.js";

function input(label: string, type: string, value: string): HTMLInputElement {
  const control = document.createElement("input");
  control.type = type;
  control.value = value;
  control.setAttribute("aria-label", label);
  return control;
}

/** Native object controls share the editor's draft and composition barriers. */
export class PdfObjectInputs {
  readonly element = document.createElement("div");
  readonly inputs = {
    x: input("Object horizontal position", "number", "20"),
    y: input("Object vertical position", "number", "20"),
    width: input("Object width", "number", "200"),
    height: input("Object height", "number", "60"),
    rotation: input("Object rotation", "number", "0"),
    font: input("Font", "text", "Arial"),
    size: input("Font size", "number", "14"),
    color: input("Text color", "text", "000000"),
    foreground: input("In front of page content", "checkbox", ""),
  };
  constructor(change: () => void) {
    for (const [key, control] of Object.entries(this.inputs)) {
      const label = document.createElement("label");
      const caption = document.createElement("span");
      label.dataset.pdfControl = `object-${key}`;
      caption.textContent = control.getAttribute("aria-label");
      label.append(caption, control);
      this.element.append(label);
    }
    this.element.addEventListener("input", change);
    this.element.addEventListener("change", change);
  }
  get signature(): string {
    return JSON.stringify(
      Object.values(this.inputs).map((control) =>
        control.type === "checkbox" ? control.checked : control.value,
      ),
    );
  }
  set(spec: PdfTextSpec): void {
    for (const key of ["x", "y", "width", "height", "rotation"] as const)
      this.inputs[key].value = String(spec.placement[key]);
    this.inputs.font.value = spec.font;
    this.inputs.size.value = String(spec.size);
    this.inputs.color.value = spec.color;
    this.inputs.foreground.checked = spec.foreground;
  }
  read(text: string, role: PdfTextSpec["role"] = "text"): PdfTextSpec {
    return {
      placement: {
        x: Number(this.inputs.x.value),
        y: Number(this.inputs.y.value),
        width: Number(this.inputs.width.value),
        height: Number(this.inputs.height.value),
        rotation: Number(this.inputs.rotation.value),
      },
      text,
      font: this.inputs.font.value,
      size: Number(this.inputs.size.value),
      color: this.inputs.color.value,
      role,
      foreground: this.inputs.foreground.checked,
    };
  }
  show(visible: boolean, text: boolean, disabled: boolean): void {
    this.element.hidden = !visible;
    for (const [key, control] of Object.entries(this.inputs)) {
      control.disabled = disabled;
      if (control.parentElement)
        control.parentElement.hidden =
          !text && ["font", "size", "color", "foreground"].includes(key);
    }
  }
}
