import type { XlsxCellFormat, XlsxFormatting } from "@open-document/wasm/xlsx";
import { DocumentError } from "@open-document/wasm/foundation";

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
  for (const source of current.fontKeys) {
    const parts = source.split("|");
    const key =
      (patch.family ?? parts[0]!) +
      ((patch.bold ?? parts.includes("bold")) ? "|bold" : "") +
      ((patch.italic ?? parts.includes("italic")) ? "|italic" : "");
    if (!profile[key])
      throw new DocumentError(
        "missing-font",
        `Missing font profile mapping: ${key}`,
        "",
        -1,
      );
  }
}
