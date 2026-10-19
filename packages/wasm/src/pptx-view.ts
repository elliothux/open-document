import { record, hasFields } from "./validation.js";

/** Source owners share the object editor; slides remain the presentation page list. */
export interface PptxEditView {
  kind: "slide" | "master" | "layout";
  slide: string;
  choices: {
    id: string;
    name: string;
    kind: "master" | "layout";
    master: string;
  }[];
  reason: string;
  operations: {
    rename: string;
    addLayout: string;
    copyLayout: string;
    deleteLayout: string;
    deleteMaster: string;
    addMaster: string;
    copyMaster: string;
  };
}

export function checkPptxEditView(
  value: unknown,
  current: unknown,
  slides: Set<string>,
): void {
  const view = record(value);
  const operations = record(view.operations);
  for (const key of [
    "rename",
    "addLayout",
    "copyLayout",
    "deleteLayout",
    "deleteMaster",
    "addMaster",
    "copyMaster",
  ])
    if (typeof operations[key] !== "string" || operations[key].length > 8192)
      throw new Error("Invalid source operation reason");
  if (
    !hasFields(view, ["kind", "slide", "reason"], []) ||
    !["slide", "master", "layout"].includes(String(view.kind)) ||
    typeof view.slide !== "string" ||
    !slides.has(view.slide) ||
    !Array.isArray(view.choices) ||
    view.choices.length > 512
  )
    throw new Error("Invalid PPTX edit view");
  const owners = new Map<string, { kind: string; master: string }>();
  let units = 0;
  for (const item of view.choices) {
    const owner = record(item);
    if (
      !hasFields(owner, ["id", "name", "kind", "master"], []) ||
      typeof owner.id !== "string" ||
      !owner.id ||
      typeof owner.master !== "string" ||
      !owner.master ||
      typeof owner.name !== "string" ||
      !["master", "layout"].includes(String(owner.kind)) ||
      owners.has(owner.id) ||
      slides.has(owner.id) ||
      [owner.id, owner.name, owner.master].some((text) => text.length > 1024)
    )
      throw new Error("Invalid PPTX source owner");
    units += owner.id.length + owner.name.length + owner.master.length;
    owners.set(owner.id, { kind: String(owner.kind), master: owner.master });
  }
  if (units > 1048576) throw new Error("PPTX source catalog exceeds budget");
  for (const [id, owner] of owners) {
    if (
      owners.get(owner.master)?.kind !== "master" ||
      (owner.kind === "master" && owner.master !== id)
    )
      throw new Error("Invalid PPTX source inheritance");
  }
  if (
    typeof current !== "string" ||
    (view.kind === "slide"
      ? current !== view.slide
      : owners.get(current)?.kind !== view.kind)
  )
    throw new Error("Invalid current PPTX source");
}
