export interface DocxPosition {
  paragraph: number;
  offset: number;
  affinity: "before" | "after";
  bidiLevel?: number;
  /** Start offset of the retained follow frame; editing still uses offset. */
  frameStart?: number;
}

export interface DocxSelection {
  anchor: DocxPosition;
  focus: DocxPosition;
}

import { record, hasFields } from "@open-document/wasm/abi/validation";
import { isDocxSelection } from "./docx-search.js";

export interface DocxHit {
  layoutId: number;
  revision: number;
  page: number;
  line: number;
  position: DocxPosition | null;
  /** Exact logical drawing range; the pointer's nearest text edge remains position. */
  drawing: DocxSelection | null;
  editable: boolean;
  reason: string;
  x: number;
  y: number;
  height: number;
}

export function docxHit(value: unknown): DocxHit {
  const object = record(value);
  const position = object.position === null ? null : record(object.position);
  if (
    !hasFields(
      value,
      ["reason"],
      ["layoutId", "revision", "page", "line", "x", "y", "height"],
    ) ||
    typeof object.editable !== "boolean" ||
    (object.drawing !== null &&
      (!isDocxSelection(object.drawing) ||
        object.editable !== true ||
        position === null ||
        object.drawing.anchor.paragraph !== position.paragraph ||
        object.drawing.focus.paragraph !== position.paragraph ||
        object.drawing.focus.offset !== object.drawing.anchor.offset + 1 ||
        (position.offset !== object.drawing.anchor.offset &&
          position.offset !== object.drawing.focus.offset))) ||
    (position !== null &&
      (!hasFields(position, ["affinity"], ["paragraph", "offset"]) ||
        (position.bidiLevel !== undefined &&
          (typeof position.bidiLevel !== "number" ||
            !Number.isInteger(position.bidiLevel) ||
            position.bidiLevel < 0 ||
            position.bidiLevel > 126)) ||
        (position.frameStart !== undefined &&
          (typeof position.frameStart !== "number" ||
            !Number.isSafeInteger(position.frameStart) ||
            position.frameStart > 2147483647 ||
            position.frameStart <= Number(position.offset))) ||
        (position.affinity !== "before" && position.affinity !== "after"))) ||
    (object.editable === true && position === null)
  )
    throw new Error("Invalid DOCX hit returned by Wasm");
  return value as DocxHit;
}

export interface DocxSelectionGeometry {
  layoutId: number;
  revision: number;
  rects: {
    page: number;
    line: number;
    x: number;
    y: number;
    width: number;
    height: number;
  }[];
}

export function docxSelectionGeometry(value: unknown): DocxSelectionGeometry {
  const object = record(value);
  const integer = (value: unknown): boolean =>
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
  if (
    !integer(object.layoutId) ||
    !integer(object.revision) ||
    !Array.isArray(object.rects) ||
    !object.rects.every((value: unknown) => {
      const rect = record(value);
      return (
        integer(rect.page) &&
        integer(rect.line) &&
        hasFields(rect, [], ["x", "y", "width", "height"]) &&
        typeof rect.width === "number" &&
        rect.width >= 0 &&
        typeof rect.height === "number" &&
        rect.height > 0
      );
    })
  )
    throw new Error("Invalid DOCX selection geometry returned by Wasm");
  return value as DocxSelectionGeometry;
}
