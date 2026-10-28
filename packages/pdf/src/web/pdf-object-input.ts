import type {
  PdfTextSpec,
  PdfDrawingAnnotation,
  PdfAnnotationStyle,
} from "../core/pdf.js";

function input(label: string, type: string, value: string): HTMLInputElement {
  const control = document.createElement("input");
  control.type = type;
  control.value = value;
  control.setAttribute("aria-label", label);
  return control;
}

/** Native object controls share the editor's draft and composition barriers. */
export class PdfObjectInputs {
  private originalAuthor: { display: string; value: string } | undefined;
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
    opacity: input("Annotation opacity", "number", "1"),
    border: input("Annotation border width", "number", "2"),
    author: input("Annotation author", "text", ""),
    points: input("Stroke points (x,y pairs)", "text", ""),
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
    this.originalAuthor = undefined;
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
  setAnnotation(style: PdfAnnotationStyle): void {
    this.set({
      placement: style.placement,
      text: style.text,
      font: "",
      size: 14,
      color: style.color,
      role: "text",
      foreground: true,
    });
    this.inputs.opacity.value = String(style.opacity);
    this.inputs.border.value = String(style.border);
    this.inputs.author.value = style.author;
    this.originalAuthor = {
      display: this.inputs.author.value,
      value: style.author,
    };
  }
  annotation(text: string): PdfAnnotationStyle {
    return {
      placement: this.read(text).placement,
      text,
      color: this.inputs.color.value,
      opacity: Number(this.inputs.opacity.value),
      border: Number(this.inputs.border.value),
      author:
        this.originalAuthor?.display === this.inputs.author.value
          ? this.originalAuthor.value
          : this.inputs.author.value,
    };
  }
  drawing(
    kind: PdfDrawingAnnotation["kind"],
    text: string,
    arrow = false,
  ): PdfDrawingAnnotation {
    return {
      kind,
      text,
      arrow,
      placement: this.read(text).placement,
      color: this.inputs.color.value,
      opacity: Number(this.inputs.opacity.value),
      border: Number(this.inputs.border.value),
      author: this.inputs.author.value,
      points: this.inputs.points.value.trim()
        ? this.inputs.points.value.split(/[,\s]+/).map(Number)
        : [],
    };
  }
  show(
    visible: boolean,
    text: boolean,
    disabled: boolean,
    layer = true,
    drawing = false,
    page?: "crop" | "resize" | "scale",
  ): void {
    this.element.hidden = !visible;
    for (const [key, control] of Object.entries(this.inputs)) {
      control.disabled = disabled || (key === "foreground" && !layer);
      if (control.parentElement)
        control.parentElement.hidden =
          (["opacity", "border", "author", "points"].includes(key) &&
            !drawing) ||
          (["font", "size", "foreground"].includes(key) &&
            (!text || drawing)) ||
          (key === "color" && !text && !drawing);
      if (control.parentElement && page)
        control.parentElement.hidden = ![
          "width",
          "height",
          ...(page === "crop" ? ["x", "y"] : []),
        ].includes(key);
    }
  }
}
