import { integer, record } from "./validation.js";
import { checkDrawingAnchor, type DrawingAnchor } from "./preview.js";
import {
  checkDocxDrawingPosition,
  type DocxDrawingPositionEdit,
} from "./docx-picture.js";

export type DocxShapePreset = "rect" | "ellipse" | "line";

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
    preset: DocxShapePreset;
    reason: string;
    sizeReason: string;
    deleteReason: string;
    anchor: DrawingAnchor | null;
    positionReason: string;
  })[];
}
export type DocxShapeEdit =
  | (Omit<DocxShape, "id"> & {
      action: "insert";
      preset: DocxShapePreset;
      /** Initial plain text; even an empty string creates an editable text box. */
      text?: string;
    })
  | (DocxShape & { action: "properties" })
  | { action: "delete"; id: number }
  | DocxDrawingPositionEdit;

export function checkDocxShapeEdit(value: unknown): void {
  const shape = record(value);
  if (shape.action === "position") return checkDocxDrawingPosition(shape);
  if (shape.action === "insert") {
    if (
      shape.preset !== "rect" &&
      shape.preset !== "ellipse" &&
      shape.preset !== "line"
    )
      throw new Error("Invalid DOCX shape preset");
    if (
      shape.text !== undefined &&
      (shape.preset === "line" ||
        typeof shape.text !== "string" ||
        shape.text.length > 32767 ||
        shape.text.split("\n").length > 256 ||
        shape.text.split("\n").some((part) => part.length > 4096) ||
        [...shape.text].some((character) => {
          const code = character.codePointAt(0)!;
          return (
            (code < 32 && code !== 9 && code !== 10) ||
            (code >= 0xd800 && code <= 0xdfff) ||
            code === 0xfffe ||
            code === 0xffff
          );
        }))
    )
      throw new Error("Invalid DOCX text box initial text");
  } else {
    if (!integer(shape.id, 0, 2147483647))
      throw new Error("Invalid DOCX shape identity");
    if (shape.action === "delete") return;
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
      !["name", "reason", "sizeReason", "deleteReason", "positionReason"].every(
        (key) => typeof shape[key] === "string",
      ) ||
      (shape.preset !== "rect" &&
        shape.preset !== "ellipse" &&
        shape.preset !== "line") ||
      (shape.preset !== "line" && (shape.width === 0 || shape.height === 0))
    )
      throw new Error("Invalid DOCX shape entry");
    seen.add(shape.id);
    checkDrawingAnchor(shape.anchor);
  }
  return value as DocxShapes;
}
