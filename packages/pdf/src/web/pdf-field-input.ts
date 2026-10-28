import type { PdfFieldDesign, PdfTextSpec } from "../core/pdf.js";

function control(label: string, type = "text"): HTMLInputElement {
  const input = document.createElement("input");
  input.type = type;
  input.setAttribute("aria-label", label);
  return input;
}

/** Field metadata shares the editor's native composition and draft barriers. */
export class PdfFieldInputs {
  readonly element = document.createElement("div");
  private kind: PdfFieldDesign["kind"] = "text";
  private loaded:
    | {
        spec: PdfFieldDesign;
        name: string;
        tooltip: string;
        options: string;
        defaultText: string;
        value: string;
      }
    | undefined;
  readonly controls = {
    name: control("Field name"),
    tooltip: document.createElement("textarea"),
    options: document.createElement("textarea"),
    defaultText: document.createElement("textarea"),
    defaultChecked: control("Default checked", "checkbox"),
    readOnly: control("Read-only field", "checkbox"),
    required: control("Required field", "checkbox"),
    multiline: control("Multiline field", "checkbox"),
    multiSelect: control("Multiple selection", "checkbox"),
    maxLength: control("Maximum text length", "number"),
    border: control("Field border width", "number"),
    background: control("Field background"),
  };
  constructor(change: () => void) {
    this.controls.tooltip.setAttribute("aria-label", "Field tooltip");
    this.controls.tooltip.maxLength = this.controls.name.maxLength = 32767;
    this.controls.options.maxLength =
      this.controls.defaultText.maxLength = 1056768;
    this.controls.options.setAttribute(
      "aria-label",
      "Options: export value and label separated by a tab, one per line",
    );
    this.controls.defaultText.setAttribute(
      "aria-label",
      "Default value; list values use separate lines",
    );
    for (const [key, input] of Object.entries(this.controls)) {
      const label = document.createElement("label"),
        caption = document.createElement("span");
      label.dataset.pdfControl = `field-${key}`;
      caption.textContent = input.getAttribute("aria-label");
      label.append(caption, input);
      this.element.append(label);
    }
    this.element.addEventListener("input", change);
    this.element.addEventListener("change", change);
  }
  get signature(): string {
    return JSON.stringify(
      Object.values(this.controls).map((input) =>
        input instanceof HTMLInputElement && input.type === "checkbox"
          ? input.checked
          : input.value,
      ),
    );
  }
  reset(kind: PdfFieldDesign["kind"], name: string): void {
    this.loaded = undefined;
    this.kind = kind;
    for (const input of Object.values(this.controls)) {
      input.value = "";
      if (input instanceof HTMLInputElement) input.checked = false;
    }
    this.controls.name.value = name;
    this.controls.maxLength.value = "32767";
    this.controls.border.value = "1";
    this.controls.background.value = "FFFFFF";
    if (["radio", "choice", "list"].includes(kind))
      this.controls.options.value = "one\tFirst option\ntwo\tSecond option";
  }
  set(spec: PdfFieldDesign): void {
    this.reset(spec.kind, spec.name);
    this.controls.tooltip.value = spec.tooltip;
    this.controls.options.value = spec.options
      .map((option) => `${option.value}\t${option.label}`)
      .join("\n");
    this.controls.defaultText.value = Array.isArray(spec.defaultValue)
      ? spec.defaultValue.join("\n")
      : String(spec.defaultValue);
    this.controls.defaultChecked.checked = spec.defaultValue === true;
    this.controls.readOnly.checked = spec.readOnly;
    this.controls.required.checked = spec.required;
    this.controls.multiline.checked = spec.multiline;
    this.controls.multiSelect.checked = spec.multiSelect;
    this.controls.maxLength.value = String(spec.maxLength);
    this.controls.border.value = String(spec.border);
    this.controls.background.value = spec.background;
    this.loaded = {
      spec: {
        ...spec,
        placement: { ...spec.placement },
        options: spec.options.map((option) => ({ ...option })),
        value: Array.isArray(spec.value) ? [...spec.value] : spec.value,
        defaultValue: Array.isArray(spec.defaultValue)
          ? [...spec.defaultValue]
          : spec.defaultValue,
      },
      name: this.controls.name.value,
      tooltip: this.controls.tooltip.value,
      options: this.controls.options.value,
      defaultText: this.controls.defaultText.value,
      value: (Array.isArray(spec.value)
        ? spec.value.join("\n")
        : String(spec.value)
      ).replace(/\r\n?/g, "\n"),
    };
  }
  show(visible: boolean, disabled: boolean, editing = false): void {
    this.element.hidden = !visible;
    for (const [key, input] of Object.entries(this.controls)) {
      input.disabled = disabled;
      const visible =
        key === "defaultChecked"
          ? this.kind === "checkbox"
          : key === "defaultText"
            ? this.kind !== "checkbox"
            : key === "options"
              ? ["radio", "choice", "list"].includes(this.kind)
              : key === "multiSelect"
                ? this.kind === "list"
                : ["maxLength", "multiline"].includes(key)
                  ? this.kind === "text"
                  : true;
      if (input.parentElement)
        input.parentElement.hidden =
          !visible || (editing && ["border", "background"].includes(key));
    }
  }
  read(spec: PdfTextSpec, value: string | boolean | string[]): PdfFieldDesign {
    const values = (text: string) => (text === "" ? [] : text.split(/\r?\n/));
    const loaded = this.loaded;
    const copyValue = (
      value: PdfFieldDesign["value"],
    ): PdfFieldDesign["value"] => (Array.isArray(value) ? [...value] : value);
    const options =
      loaded && this.controls.options.value === loaded.options
        ? loaded.spec.options.map((option) => ({ ...option }))
        : ["radio", "choice", "list"].includes(this.kind)
          ? values(this.controls.options.value).map((line) => {
              const parts = line.split("\t");
              if (parts.length > 2)
                throw new Error(
                  "Each field option uses one export value and one label",
                );
              return { value: parts[0]!, label: parts[1] ?? parts[0]! };
            })
          : [];
    return {
      kind: this.kind,
      name:
        loaded && this.controls.name.value === loaded.name
          ? loaded.spec.name
          : this.controls.name.value,
      tooltip:
        loaded && this.controls.tooltip.value === loaded.tooltip
          ? loaded.spec.tooltip
          : this.controls.tooltip.value,
      placement: spec.placement,
      font:
        loaded && spec.font === loaded.spec.font.replace(/[\r\n]/g, "")
          ? loaded.spec.font
          : spec.font,
      size: spec.size,
      color: spec.color,
      value:
        loaded &&
        typeof value === "string" &&
        value.replace(/\r\n?/g, "\n") === loaded.value
          ? copyValue(loaded.spec.value)
          : this.kind === "list"
            ? Array.isArray(value)
              ? [...value]
              : values(String(value))
            : value,
      defaultValue:
        this.kind === "checkbox"
          ? this.controls.defaultChecked.checked
          : loaded && this.controls.defaultText.value === loaded.defaultText
            ? copyValue(loaded.spec.defaultValue)
            : this.kind === "list"
              ? values(this.controls.defaultText.value)
              : this.controls.defaultText.value,
      options,
      readOnly: this.controls.readOnly.checked,
      required: this.controls.required.checked,
      multiline: this.controls.multiline.checked,
      multiSelect: this.controls.multiSelect.checked,
      maxLength: Number(this.controls.maxLength.value),
      border: Number(this.controls.border.value),
      background: this.controls.background.value,
    };
  }
}
