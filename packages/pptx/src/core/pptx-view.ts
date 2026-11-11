import {
  pptxGridSpacingMaxPoints,
  pptxGridUnitsPerPoint,
  pptxGuideCount,
} from "@open-document/wasm/engine-source";
import { record } from "@open-document/wasm/abi/validation";

export interface PptxSizeMatch {
  object: string;
  width: boolean;
  height: boolean;
  outline: { x: number; y: number }[];
}
export interface PptxSpacing {
  axis: "x" | "y";
  from: number;
  to: number;
  at: number;
}
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
    settings.spacing < 1 / pptxGridUnitsPerPoint ||
    settings.spacing > pptxGridSpacingMaxPoints
  )
    throw new Error("Invalid presentation snapping settings");
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
    !Array.isArray(guides.items) ||
    guides.items.length > pptxGuideCount
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
