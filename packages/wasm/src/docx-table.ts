import { record } from "./validation.js";
import { isDocxSelection } from "./docx-search.js";
import type { DocxSelection } from "./docx-hit.js";

export interface DocxFragmentImages {
  revision: number;
  images: { key: string; bytes: Uint8Array }[];
}
export function docxFragmentImages(
  value: unknown,
  encoded: boolean,
): DocxFragmentImages {
  const result = record(value);
  if (
    typeof result.revision !== "number" ||
    !Number.isInteger(result.revision) ||
    result.revision < 0 ||
    !Array.isArray(result.images) ||
    result.images.length > 256
  )
    throw new Error("Invalid fragment images");
  const images: unknown[] = result.images;
  const keys = new Set<string>();
  let size = 0;
  return {
    revision: result.revision,
    images: images.map((value) => {
      const image = record(value);
      if (
        typeof image.key !== "string" ||
        !image.key ||
        image.key.length > 256 ||
        keys.has(image.key) ||
        (encoded
          ? typeof image.bytes !== "string"
          : !(image.bytes instanceof Uint8Array))
      )
        throw new Error("Invalid fragment image resource");
      keys.add(image.key);
      let bytes: Uint8Array;
      if (encoded) {
        if (typeof image.bytes !== "string" || image.bytes.length > 2097152)
          throw new Error("Invalid encoded image bytes");
        bytes = Uint8Array.from(atob(image.bytes), (value) =>
          value.charCodeAt(0),
        );
      } else {
        if (!(image.bytes instanceof Uint8Array))
          throw new Error("Invalid decoded image bytes");
        bytes = image.bytes;
      }
      size += bytes.length;
      if (!bytes.length || size > 2097152)
        throw new Error("Fragment image bytes exceed budget");
      return { key: image.key, bytes };
    }),
  };
}

export interface DocxTableClipboard {
  text: string;
  selection: DocxSelection;
  fragment: string | null;
  reason: string;
}

export function docxTableClipboard(value: unknown): DocxTableClipboard {
  const result = record(value);
  if (
    typeof result.text !== "string" ||
    result.text.length > 65536 ||
    (result.fragment !== null &&
      (typeof result.fragment !== "string" ||
        result.fragment.length === 0 ||
        result.fragment.length > 2097152)) ||
    typeof result.reason !== "string" ||
    !isDocxSelection(result.selection)
  )
    throw new Error("Invalid table clipboard returned by Wasm");
  return value as DocxTableClipboard;
}

export interface DocxBorderStyle {
  width: number;
  color: string;
}
export type DocxBorderSide =
  "top" | "right" | "bottom" | "left" | "insideH" | "insideV";
export type DocxBorderPatch = Partial<
  Record<DocxBorderSide, DocxBorderStyle | null>
>;
export type DocxCellBorders = Record<
  "top" | "right" | "bottom" | "left",
  DocxBorderStyle | null
>;
export type DocxTableBorders = DocxCellBorders &
  Record<"insideH" | "insideV", DocxBorderStyle | null>;

export function checkDocxBorders(value: unknown, wholeTable: boolean): void {
  const patch = record(value),
    keys = Object.keys(patch);
  if (!keys.length) throw new Error("Border changes are empty");
  for (const key of keys) {
    if (
      ![
        "top",
        "right",
        "bottom",
        "left",
        ...(wholeTable ? ["insideH", "insideV"] : []),
      ].includes(key)
    )
      throw new Error("Invalid border side");
    if (patch[key] === null) continue;
    const edge = record(patch[key]),
      width = edge.width;
    if (
      Object.keys(edge).length !== 2 ||
      typeof width !== "number" ||
      !Number.isFinite(width) ||
      (width !== 0 && width < 0.25) ||
      width > 12 ||
      !Number.isInteger(width * 8) ||
      typeof edge.color !== "string" ||
      !/^[0-9a-f]{6}$/i.test(edge.color)
    )
      throw new Error("Invalid border width or color");
  }
}

export interface DocxCellMargins {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export function checkDocxCellMargins(value: unknown): void {
  const margins = record(value);
  if (
    !["top", "right", "bottom", "left"].every((key) => {
      const number = margins[key];
      return (
        typeof number === "number" &&
        Number.isFinite(number) &&
        number >= 0 &&
        number <= 14400 &&
        Number.isInteger(number * 20)
      );
    })
  )
    throw new Error("Invalid cell margins");
}

export type DocxTableEdit =
  | { action: "pasteCells"; text: string }
  | { action: "pasteFragment"; fragment: string }
  | { action: "autoFit"; mode: "content" | "page" | "fixed" }
  | { action: "tableBorders" | "cellBorders"; value: DocxBorderPatch }
  | {
      action:
        | "rowBefore"
        | "rowAfter"
        | "deleteRow"
        | "columnBefore"
        | "columnAfter"
        | "deleteColumn"
        | "unmerge"
        | "splitTable";
    }
  | { action: "merge" | "splitCell"; rows: number; columns: number }
  | { action: "tableWidth"; value: number }
  | { action: "rowHeight"; value: number; rule: "atLeast" | "exact" }
  | { action: "columnWidth"; column: number; value: number }
  | { action: "headerRows"; value: number }
  | { action: "rowSplit"; value: boolean }
  | { action: "cellFill"; value: string | null }
  | { action: "cellVerticalAlign"; value: "top" | "center" | "bottom" | null }
  | { action: "cellMargins" | "tableMargins"; value: DocxCellMargins | null }
  | { action: "tableAlign"; value: "left" | "center" | "right" };

export function checkDocxTableEdit(value: unknown): void {
  const change = record(value);
  if (change.action === "pasteFragment") {
    if (
      typeof change.fragment !== "string" ||
      change.fragment.length === 0 ||
      change.fragment.length > 2097152 ||
      Object.keys(change).some((key) => key !== "action" && key !== "fragment")
    )
      throw new Error("Invalid rich table clipboard");
    return;
  }
  if (change.action === "pasteCells") {
    if (
      typeof change.text !== "string" ||
      change.text.length > 65536 ||
      Object.keys(change).some((key) => key !== "action" && key !== "text")
    )
      throw new Error("Invalid table clipboard text");
    return;
  }
  if (change.action === "rowSplit") {
    if (typeof change.value !== "boolean")
      throw new Error("Invalid row split setting");
    return;
  }
  if (change.action === "autoFit") {
    if (!["content", "page", "fixed"].includes(String(change.mode)))
      throw new Error("Invalid table fitting mode");
    return;
  }
  if (change.action === "tableBorders" || change.action === "cellBorders") {
    checkDocxBorders(change.value, change.action === "tableBorders");
    return;
  }
  if (change.action === "headerRows") {
    if (
      typeof change.value !== "number" ||
      !Number.isSafeInteger(change.value) ||
      change.value < 0 ||
      change.value > 1000
    )
      throw new Error("Invalid header row count");
    return;
  }
  if (change.action === "tableAlign") {
    if (
      typeof change.value !== "string" ||
      !["left", "center", "right"].includes(change.value)
    )
      throw new Error("Invalid table alignment");
    return;
  }
  if (change.action === "cellMargins" || change.action === "tableMargins") {
    if (change.value !== null) checkDocxCellMargins(change.value);
    return;
  }
  if (change.action === "cellVerticalAlign") {
    if (
      change.value !== null &&
      (typeof change.value !== "string" ||
        !["top", "center", "bottom"].includes(change.value))
    )
      throw new Error("Invalid cell vertical alignment");
    return;
  }
  if (change.action === "cellFill") {
    if (
      change.value !== null &&
      (typeof change.value !== "string" || !/^[0-9a-f]{6}$/i.test(change.value))
    )
      throw new Error("Invalid cell fill");
    return;
  }
  if (
    change.action === "tableWidth" ||
    change.action === "rowHeight" ||
    change.action === "columnWidth"
  ) {
    if (
      change.action === "rowHeight" &&
      !["atLeast", "exact"].includes(String(change.rule))
    )
      throw new Error("Invalid row height rule");
    if (
      change.action === "columnWidth" &&
      (typeof change.column !== "number" ||
        !Number.isSafeInteger(change.column) ||
        change.column < 0 ||
        change.column >= 63 ||
        typeof change.value !== "number" ||
        change.value < 12)
    )
      throw new Error("Invalid column width or index");
    if (
      typeof change.value !== "number" ||
      !Number.isFinite(change.value) ||
      change.value < 0 ||
      change.value > 14400 ||
      !Number.isInteger(change.value * 20) ||
      (change.action === "tableWidth" && change.value === 0)
    )
      throw new Error("Invalid table size");
    return;
  }
  if (
    (change.action === "merge" || change.action === "splitCell") &&
    typeof change.rows === "number" &&
    typeof change.columns === "number"
  ) {
    checkDocxTableSize(change.rows, change.columns);
    return;
  }
  if (
    typeof change.action !== "string" ||
    ![
      "rowBefore",
      "rowAfter",
      "deleteRow",
      "columnBefore",
      "columnAfter",
      "deleteColumn",
      "unmerge",
      "splitTable",
    ].includes(change.action)
  )
    throw new Error("Invalid table edit");
}

/** Bounds match the core's table creation limit. */
export function checkDocxTableSize(rows: number, columns: number): void {
  if (
    !Number.isInteger(rows) ||
    !Number.isInteger(columns) ||
    rows < 1 ||
    rows > 1000 ||
    columns < 1 ||
    columns > 63 ||
    rows * columns > 4096
  )
    throw new Error("Invalid table dimensions");
}
