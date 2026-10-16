import {
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
  type XlsxFormatting,
} from "@open-document/wasm/xlsx";
import { DocumentError } from "@open-document/wasm/foundation";

export function checkFontMapping(
  key: string,
  profile: Record<string, string>,
): void {
  if (!profile[key])
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
  for (const row of format)
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
