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
    const page = field.widgets[0]?.page || state.page;
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
