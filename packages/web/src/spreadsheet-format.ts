import {
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
  type XlsxFormatting,
  type XlsxQuery,
} from "@open-document/wasm/xlsx";
import type { XlsxClient } from "./xlsx.js";
import { DocumentError } from "@open-document/wasm/foundation";

export function autoFitGrid(
  client: XlsxClient,
  query: XlsxQuery,
  axis: "rows" | "columns",
  profile: Record<string, string>,
) {
  const range = query.selection.range;
  return client.autoFit(
    query.revision,
    query.sheet,
    axis === "rows" ? range.top : range.left,
    axis === "rows" ? range.bottom : range.right,
    axis,
    profile,
  );
}

export function formatGrid(
  client: XlsxClient,
  query: XlsxQuery,
  patch: XlsxCellFormat,
  profile: Record<string, string>,
) {
  checkFormatFonts(patch, query.formatting, profile);
  return client.formatCells(query.revision, patch);
}

export function checkFontMapping(
  key: string,
  profile: Record<string, string>,
): void {
  const parts = key.split("|");
  const fallback = `*${parts.includes("bold") ? "|bold" : ""}${parts.includes("italic") ? "|italic" : ""}`;
  if (!profile[key] && !profile[fallback] && !profile["*"])
    throw new DocumentError(
      "missing-font",
      `Missing font profile mapping: ${key}`,
      "",
      -1,
    );
}

export function checkCopiedFormatFonts(
  format: CopiedCellFormat,
  current: XlsxFormatting,
  profile: Record<string, string>,
): void {
  copiedCellFormat(format);
  for (const row of format.cells)
    for (const patch of row) checkFormatFonts(patch, current, profile);
}

export function checkFormatFonts(
  patch: XlsxCellFormat,
  current: XlsxFormatting,
  profile: Record<string, string>,
): void {
  if (
    patch.family === undefined &&
    patch.bold === undefined &&
    patch.italic === undefined
  )
    return;
  const sources =
    patch.family !== undefined &&
    patch.bold !== undefined &&
    patch.italic !== undefined
      ? [patch.family]
      : current.fontKeys;
  for (const source of sources) {
    const parts = source.split("|");
    const key =
      (patch.family ?? parts[0]!) +
      ((patch.bold ?? parts.includes("bold")) ? "|bold" : "") +
      ((patch.italic ?? parts.includes("italic")) ? "|italic" : "");
    checkFontMapping(key, profile);
  }
}
