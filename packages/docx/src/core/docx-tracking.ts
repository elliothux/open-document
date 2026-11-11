import { docxRevisionAuthorUnits } from "@open-document/wasm/engine-source";

export interface DocxTracking {
  revision: number;
  enabled: boolean;
  author: string;
  reason: string;
}

export function checkTrackingAuthor(
  value: unknown,
): asserts value is string | null {
  if (
    value !== null &&
    (typeof value !== "string" ||
      value.length > docxRevisionAuthorUnits ||
      !value.trim() ||
      !value.isWellFormed() ||
      Array.from(value).some(
        (ch) => ch.codePointAt(0)! < 32 || ch === "\ufffe" || ch === "\uffff",
      ))
  )
    throw new Error("Invalid revision author");
}
