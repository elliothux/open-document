import type { DocxPosition, DocxSelection } from "./foundation.js";
import { record, hasFields } from "./validation.js";
import { isDocxSelection } from "./docx-search.js";

export interface DocxHit {
  layoutId: number;
  revision: number;
  page: number;
  line: number;
  position: DocxPosition | null;
  /** Exact logical image range; the pointer's nearest text edge remains position. */
  picture: DocxSelection | null;
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
    (object.picture !== null &&
      (!isDocxSelection(object.picture) ||
        object.editable !== true ||
        position === null ||
        object.picture.anchor.paragraph !== position.paragraph ||
        object.picture.focus.paragraph !== position.paragraph ||
        object.picture.focus.offset !== object.picture.anchor.offset + 1 ||
        (position.offset !== object.picture.anchor.offset &&
          position.offset !== object.picture.focus.offset))) ||
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
