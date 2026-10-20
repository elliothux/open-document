import { record, hasFields } from "./validation.js";

export interface PptxSnapSettings {
  grid: boolean;
  objects: boolean;
  spacing: number;
}
export interface PptxSnapping extends PptxSnapSettings {
  reason: string;
}
export function checkPptxSnapSettings(value: unknown): void {
  const settings = record(value);
  if (
    Object.keys(settings).length !== 3 ||
    typeof settings.grid !== "boolean" ||
    typeof settings.objects !== "boolean" ||
    typeof settings.spacing !== "number" ||
    !Number.isFinite(settings.spacing) ||
    settings.spacing < 1 / 12700 ||
    settings.spacing > 144
  )
    throw new Error("Invalid presentation snapping settings");
}
export function checkPptxSnapping(value: unknown): void {
  const { reason, ...settings } = record(value);
  checkPptxSnapSettings(settings);
  if (typeof reason !== "string" || reason.length > 8192)
    throw new Error("Invalid presentation snapping reason");
}

export interface PptxGuide {
  orientation: "horz" | "vert";
  position: number;
}
export interface PptxGuides {
  visible: boolean;
  items: PptxGuide[];
  reason: string;
}
export function checkPptxGuides(value: unknown): void {
  const guides = record(value);
  if (
    typeof guides.visible !== "boolean" ||
    typeof guides.reason !== "string" ||
    guides.reason.length > 8192 ||
    !Array.isArray(guides.items) ||
    guides.items.length > 64
  )
    throw new Error("Invalid presentation guides");
  for (const item of guides.items) {
    const guide = record(item);
    if (
      Object.keys(guide).length !== 2 ||
      (guide.orientation !== "horz" && guide.orientation !== "vert") ||
      typeof guide.position !== "number" ||
      !Number.isFinite(guide.position) ||
      guide.position < -268435456 ||
      guide.position > 268435455.875
    )
      throw new Error("Invalid presentation guide");
  }
}
import {
  checkPptxTextFormat,
  checkPptxParagraphFormat,
  checkPptxParagraphFormatting,
  type PptxTextFormat,
  type PptxParagraphFormat,
  type PptxParagraphFormatting,
} from "./pptx-format.js";

export type PptxMasterParagraphFormat = Omit<PptxParagraphFormat, "level"> & {
  alignment?: "left" | "center" | "right" | "justify";
};
export interface PptxMasterParagraphStyle extends PptxParagraphFormatting {
  alignment: "left" | "center" | "right" | "justify" | null;
}

export interface PptxMasterTextStyle {
  kind: "title" | "body" | "other";
  level: number;
  format: PptxTextFormat | null;
  reason: string;
  paragraph: PptxMasterParagraphStyle;
}
export interface PptxMasterTextStyles {
  items: PptxMasterTextStyle[];
  reason: string;
}

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
  textStyles: PptxMasterTextStyles;
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
  checkPptxMasterTextStyles(view.textStyles, view.kind);
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

export function checkPptxMasterTextStyles(value: unknown, kind: unknown): void {
  const styles = record(value);
  if (
    typeof styles.reason !== "string" ||
    styles.reason.length > 8192 ||
    !Array.isArray(styles.items) ||
    (styles.items.length !== 0 &&
      (kind !== "master" || styles.items.length !== 27)) ||
    (styles.items.length === 0 && styles.reason === "" && kind === "master")
  )
    throw new Error("Invalid master text styles query");
  const slots = new Set<string>();
  for (const item of styles.items) {
    const slot = record(item);
    const paragraph = record(slot.paragraph);
    checkPptxParagraphFormatting(paragraph);
    if (
      typeof paragraph.reason !== "string" ||
      paragraph.reason.length > 8192 ||
      (paragraph.alignment !== null &&
        (typeof paragraph.alignment !== "string" ||
          !["left", "center", "right", "justify"].includes(
            paragraph.alignment,
          ))) ||
      (!paragraph.reason &&
        (paragraph.level !== slot.level ||
          Object.values(paragraph).some((value) => value === null)))
    )
      throw new Error("Invalid master paragraph style query");
    if (
      typeof slot.kind !== "string" ||
      !["title", "body", "other"].includes(slot.kind) ||
      typeof slot.level !== "number" ||
      !Number.isInteger(slot.level) ||
      slot.level < 0 ||
      slot.level > 8 ||
      typeof slot.reason !== "string" ||
      slot.reason.length > 8192
    )
      throw new Error("Invalid master text style slot");
    const key = `${slot.kind}:${slot.level}`;
    if (slots.has(key)) throw new Error("Duplicate master text style slot");
    slots.add(key);
    if (slot.format !== null) {
      checkPptxTextFormat(slot.format);
      if (Object.keys(record(slot.format)).length !== 9)
        throw new Error("Incomplete master text style format");
    } else if (!slot.reason)
      throw new Error("Missing master text style format");
  }
}

export function checkPptxMasterStyleEdit(value: unknown): void {
  const change = record(value);
  if (
    Object.keys(change).length !== 4 ||
    typeof change.kind !== "string" ||
    !["title", "body", "other"].includes(change.kind) ||
    typeof change.level !== "number" ||
    !Number.isInteger(change.level) ||
    change.level < 0 ||
    change.level > 8
  )
    throw new Error("Invalid master style edit");
  if (change.action === "masterTextStyle") {
    if (change.format !== null) checkPptxTextFormat(change.format);
    return;
  }
  if (change.action !== "masterParagraphStyle")
    throw new Error("Invalid master style action");
  if (change.format === null) return;
  const format = record(change.format),
    { alignment, ...paragraph } = format;
  if (
    !Object.keys(format).length ||
    "level" in format ||
    ("alignment" in format &&
      (typeof alignment !== "string" ||
        !["left", "center", "right", "justify"].includes(alignment)))
  )
    throw new Error("Invalid master paragraph style edit");
  if (Object.keys(paragraph).length) checkPptxParagraphFormat(paragraph);
}
