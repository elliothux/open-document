import { integer, record } from "./validation.js";
import { checkDrawingAnchor, type DrawingAnchor } from "./preview.js";
import {
  checkDocxDrawingPosition,
  type DocxDrawingPositionEdit,
  checkDocxDrawingHyperlinkEdit,
  checkDocxDrawingHyperlink,
  type DocxDrawingHyperlinkEdit,
  type DocxDrawingHyperlink,
} from "./docx-picture.js";

export type DocxShapePreset = "rect" | "ellipse" | "line";

export interface DocxTextBoxProperties {
  /** Top, right, bottom and left text margins, in points. */
  insets: [number, number, number, number];
  anchor: "t" | "ctr" | "b";
  wrap: boolean;
  /** Clip both overflow axes to the frame. */
  clip: boolean;
}

export interface DocxShape {
  id: number;
  width: number;
  height: number;
  /** Six RGB hex digits, or an empty string for no fill. */
  fill: string;
  stroke: string;
  lineWidth: number;
}
export interface DocxShapes {
  revision: number;
  items: (DocxShape & {
    name: string;
    selected: boolean;
    preset: DocxShapePreset | "polyline";
    reason: string;
    sizeReason: string;
    deleteReason: string;
    anchor: DrawingAnchor | null;
    positionReason: string;
    textBox: DocxTextBoxProperties | null;
    textReason: string;
    hyperlink: DocxDrawingHyperlink;
  })[];
}
export type DocxShapeEdit =
  | {
      action: "insertWordArt";
      preset: "blue" | "gold" | "red" | "purple" | "green-italic";
      text: string;
    }
  | (Omit<DocxShape, "id"> & {
      action: "insert";
      preset: DocxShapePreset;
      /** Initial plain text; even an empty string creates an editable text box. */
      text?: string;
    })
  | (DocxShape & { action: "properties" })
  | { action: "textBox"; id: number; properties: DocxTextBoxProperties }
  | { action: "delete"; id: number }
  | DocxDrawingHyperlinkEdit
  | DocxDrawingPositionEdit;

export function checkDocxShapeEdit(value: unknown): void {
  const shape = record(value);
  if (shape.action === "hyperlink") return checkDocxDrawingHyperlinkEdit(shape);
  if (shape.action === "position") return checkDocxDrawingPosition(shape);
  if (shape.action === "insertWordArt") {
    if (
      typeof shape.preset !== "string" ||
      !["blue", "gold", "red", "purple", "green-italic"].includes(
        shape.preset,
      ) ||
      typeof shape.text !== "string" ||
      !shape.text.trim()
    )
      throw new Error("Invalid solid WordArt preset or text");
    checkTextBoxText(shape.text);
    return;
  }
  if (shape.action === "insert") {
    if (
      shape.preset !== "rect" &&
      shape.preset !== "ellipse" &&
      shape.preset !== "line"
    )
      throw new Error("Invalid DOCX shape preset");
    if (shape.text !== undefined) {
      if (shape.preset === "line")
        throw new Error("Line shapes cannot contain text");
      checkTextBoxText(shape.text);
    }
  } else {
    if (!integer(shape.id, 0, 2147483647))
      throw new Error("Invalid DOCX shape identity");
    if (shape.action === "delete") return;
    if (shape.action === "textBox") {
      checkTextBoxProperties(shape.properties);
      return;
    }
    if (shape.action !== "properties")
      throw new Error("Invalid DOCX shape action");
  }
  if (
    ![shape.width, shape.height].every(
      (v) =>
        typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 14400,
    ) ||
    (shape.width === 0 && shape.height === 0) ||
    (shape.action === "insert" &&
      shape.preset !== "line" &&
      (shape.width === 0 || shape.height === 0)) ||
    ![shape.fill, shape.stroke].every(
      (v) => typeof v === "string" && /^(?:[a-f\d]{6})?$/i.test(v),
    ) ||
    typeof shape.lineWidth !== "number" ||
    !Number.isFinite(shape.lineWidth) ||
    shape.lineWidth < 0 ||
    shape.lineWidth > 1584 ||
    (shape.stroke !== "" && shape.lineWidth === 0)
  )
    throw new Error("Invalid DOCX shape dimensions or paint");
}

function checkTextBoxText(text: unknown): void {
  if (
    typeof text !== "string" ||
    text.length > 32767 ||
    text.split("\n").length > 256 ||
    text.split("\n").some((part) => part.length > 4096) ||
    [...text].some((character) => {
      const code = character.codePointAt(0)!;
      return (
        (code < 32 && code !== 9 && code !== 10) ||
        (code >= 0xd800 && code <= 0xdfff) ||
        code === 0xfffe ||
        code === 0xffff
      );
    })
  )
    throw new Error("Invalid DOCX text box initial text");
}

function checkTextBoxProperties(value: unknown): void {
  const body = record(value);
  if (
    !Array.isArray(body.insets) ||
    body.insets.length !== 4 ||
    !body.insets.every(
      (v) =>
        typeof v === "number" && Number.isFinite(v) && v >= 0 && v <= 14400,
    ) ||
    (body.anchor !== "t" && body.anchor !== "ctr" && body.anchor !== "b") ||
    typeof body.wrap !== "boolean" ||
    typeof body.clip !== "boolean"
  )
    throw new Error("Invalid DOCX text box properties");
}

export function docxShapes(value: unknown): DocxShapes {
  const source = record(value);
  if (
    !integer(source.revision, 0, 2147483647) ||
    !Array.isArray(source.items) ||
    source.items.length > 256
  )
    throw new Error("Invalid DOCX shape catalog");
  const seen = new Set<number>();
  for (const entry of source.items) {
    const shape = record(entry);
    checkDocxShapeEdit({ ...shape, action: "properties" });
    if (
      typeof shape.id !== "number" ||
      typeof shape.selected !== "boolean" ||
      !integer(shape.id, 0, 2147483647) ||
      seen.has(shape.id) ||
      ![
        "name",
        "reason",
        "sizeReason",
        "deleteReason",
        "positionReason",
        "textReason",
      ].every((key) => typeof shape[key] === "string") ||
      (shape.preset !== "rect" &&
        shape.preset !== "ellipse" &&
        shape.preset !== "line" &&
        shape.preset !== "polyline") ||
      (shape.preset !== "line" && (shape.width === 0 || shape.height === 0))
    )
      throw new Error("Invalid DOCX shape entry");
    seen.add(shape.id);
    checkDrawingAnchor(shape.anchor);
    checkDocxDrawingHyperlink(shape.hyperlink);
    if (shape.textBox !== null) {
      if (shape.preset === "line" || shape.preset === "polyline")
        throw new Error("Line shapes cannot contain text");
      checkTextBoxProperties(shape.textBox);
    }
  }
  return value as DocxShapes;
}
