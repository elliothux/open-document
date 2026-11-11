import type { PdfObjectDrag } from "./pdf-object-drag.js";
import type { PdfQuery } from "../core/pdf.js";
import type { PdfClient } from "./pdf.js";
import type { PdfPropertyInputs } from "./pdf-property-input.js";
import { pdfTextRole, type Draft } from "./pdf-draft.js";

export async function propertyDraft(
  value: string,
  controls: PdfPropertyInputs,
  state: PdfQuery,
  client: PdfClient,
  profile: Record<string, string>,
  paint: (page: string) => Promise<void>,
): Promise<Draft | undefined> {
  let draft: Draft | undefined;
  if (value.startsWith("object:")) {
    const objects = await client.execute({
      operation: "pdfObjects",
      profile: profile,
      revision: state.revision,
      page: state.page,
    });
    const object = objects.objects.find(
      (item) => `object:${item.id}` === value,
    );
    if (!object) throw new Error("Unknown PDF object");
    controls.objectInputs.set({
      placement: object.placement,
      text: object.text,
      font: object.font || "Arial",
      size: object.size || 14,
      color: object.color || "000000",
      role: "text",
      foreground: object.foreground,
    });
    draft = {
      kind: object.kind === "text" ? "textObject" : "objectGeometry",
      id: object.id,
      page: state.page,
      original: object.text,
      originalSpec: controls.objectInputs.signature,
      reason: object.readOnlyReason,
      role: pdfTextRole(object.role),
    };
    controls.text.value = object.text;
  } else if (value.startsWith("metadata:")) {
    const key = value.slice("metadata:".length);
    if (!["Title", "Author", "Subject", "Keywords"].includes(key))
      throw new Error("Unknown PDF metadata");
    const metadata = await client.execute({ operation: "pdfMetadata" });
    const entry = Object.entries(metadata.fields).find(
      ([name]) => name === key,
    );
    if (!entry) throw new Error("Missing PDF metadata");
    draft = {
      kind: "metadata",
      id: key,
      page: state.page,
      original: entry[1],
      reason: metadata.readOnlyReason,
    };
    controls.text.value = entry[1];
  } else if (value.startsWith("field:")) {
    const field = state.fields.find((field) => `field:${field.id}` === value);
    if (!field) throw new Error("Unknown PDF field");
    const page = field.widgets.some((widget) => widget.page === state.page)
      ? state.page
      : field.widgets[0]?.page || state.page;
    if (page !== state.page) await paint(page);
    draft = {
      kind: "field",
      id: field.id,
      page,
      original: Array.isArray(field.value)
        ? [...field.value]
        : typeof field.value === "boolean"
          ? field.value
          : String(field.value ?? ""),
    };
    controls.text.value = typeof field.value === "string" ? field.value : "";
    controls.fieldChoice.multiple = field.multiSelect;
    controls.fieldChoice.size = field.kind === "list" ? 4 : 1;
    controls.fieldChoice.replaceChildren(
      ...(field.kind === "list" ? [] : [new Option("", "")]),
      ...field.options.map((option) => new Option(option.label, option.value)),
    );
    controls.fieldChoice.value =
      typeof field.value === "string" ? field.value : "";
    if (Array.isArray(field.value))
      for (const option of controls.fieldChoice.options)
        option.selected = field.value.includes(option.value);
    controls.checked.checked = field.value === true;
  } else if (value.startsWith("annotation:")) {
    const annotation = state.annotations.find(
      (item) => `annotation:${item.id}` === value,
    );
    if (!annotation) throw new Error("Unknown PDF annotation");
    if (annotation.page !== state.page) await paint(annotation.page);
    draft = {
      kind: "annotation",
      id: annotation.id,
      page: annotation.page,
      original: annotation.text,
    };
    controls.text.value = annotation.text;
  } else draft = undefined;
  return draft;
}

export function renderPdfPropertyDraft(
  controls: PdfPropertyInputs,
  draft: Draft | undefined,
  field: PdfQuery["fields"][number] | undefined,
  paused: boolean,
  applying: boolean,
  propertyReason: string,
  objectDrag: PdfObjectDrag,
): void {
  controls.text.hidden =
    !draft ||
    typeof draft.original === "boolean" ||
    draft.kind === "objectGeometry" ||
    draft.kind === "pageGeometry" ||
    draft.kind === "imageCrop" ||
    (!!field && ["radio", "choice", "list"].includes(field.kind));
  controls.fieldChoice.hidden =
    !field || !["radio", "choice", "list"].includes(field.kind);
  controls.checked.hidden = !draft || typeof draft.original !== "boolean";
  controls.x.hidden = controls.y.hidden =
    draft?.kind !== "note" && draft?.kind !== "fieldCopy";
  for (const [input, axis] of [
    [controls.x, "horizontal"],
    [controls.y, "vertical"],
  ] as const) {
    input.min = draft?.kind === "fieldCopy" ? "-14400" : "0";
    const label =
      draft?.kind === "fieldCopy"
        ? `Field ${axis} offset`
        : `Note ${axis} position`;
    input.setAttribute("aria-label", label);
    const caption = input.parentElement?.querySelector("span");
    if (caption) caption.textContent = label;
  }
  for (const input of [
    controls.text,
    controls.checked,
    controls.fieldChoice,
    controls.x,
    controls.y,
  ])
    if (input.parentElement) input.parentElement.hidden = input.hidden;
  controls.text.rows = field?.multiline ? 4 : 2;
  controls.text.maxLength = field?.maxLength ?? controls.textUnits;
  controls.text.disabled = controls.checked.disabled =
    paused || applying || !!propertyReason;
  controls.x.disabled = controls.y.disabled = controls.text.disabled;
  controls.fieldChoice.disabled = controls.text.disabled;
  controls.fieldInputs.show(
    draft?.kind === "newField" || draft?.kind === "fieldDesign",
    controls.text.disabled,
    draft?.kind === "fieldDesign",
  );
  controls.widgetInputs.show(
    draft?.kind === "fieldDesign",
    controls.text.disabled,
  );
  controls.inkInputs.show(draft?.kind === "newInk", controls.text.disabled);
  controls.cropInputs.show(draft?.kind === "imageCrop", controls.text.disabled);
  controls.objectInputs.show(
    draft?.originalSpec !== undefined && draft.kind !== "imageCrop",
    draft?.kind !== "objectGeometry",
    controls.text.disabled,
    !draft?.id.includes("/source/"),
    draft?.kind === "newDrawing" ||
      draft?.kind === "newInk" ||
      draft?.kind === "annotationStyle" ||
      draft?.kind === "annotationReply",
    draft?.kind === "pageGeometry" ? draft.pageAction : undefined,
  );
  if (draft?.kind === "newField")
    for (const key of ["rotation", "foreground"] as const) {
      const label = controls.objectInputs.inputs[key].parentElement;
      if (label) label.hidden = true;
    }
  if (draft?.kind === "fieldDesign")
    for (const key of [
      "x",
      "y",
      "width",
      "height",
      "rotation",
      "foreground",
    ] as const) {
      const label = controls.objectInputs.inputs[key].parentElement;
      if (label) label.hidden = true;
    }
  if (
    draft?.kind === "newDrawing" ||
    draft?.kind === "newInk" ||
    draft?.kind === "annotationStyle"
  )
    for (const key of ["rotation", "points"] as const) {
      const label = controls.objectInputs.inputs[key].parentElement;
      if (label && (key !== "points" || draft.kind !== "newDrawing"))
        label.hidden = true;
    }
  if (draft?.kind === "annotationReply")
    for (const [key, control] of Object.entries(controls.objectInputs.inputs)) {
      if (control.parentElement)
        control.parentElement.hidden = key !== "author";
    }
  const movable =
    !paused &&
    !applying &&
    !propertyReason &&
    (draft?.kind === "textObject" || draft?.kind === "objectGeometry");
  objectDrag.show(
    movable ? draft.page : undefined,
    movable ? draft.id : undefined,
  );
}
