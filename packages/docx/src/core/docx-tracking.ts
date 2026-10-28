import { integer, record } from "@open-document/wasm/abi/validation";

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
      value.length > 255 ||
      !value.trim() ||
      !value.isWellFormed() ||
      Array.from(value).some(
        (ch) => ch.codePointAt(0)! < 32 || ch === "\ufffe" || ch === "\uffff",
      ))
  )
    throw new Error("Invalid revision author");
}

export function docxTracking(value: unknown): DocxTracking {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.enabled !== "boolean" ||
    typeof result.author !== "string" ||
    typeof result.reason !== "string" ||
    (result.enabled ? !result.author.trim() : result.author !== "")
  )
    throw new Error("Invalid revision recording state");
  checkTrackingAuthor(result.enabled ? result.author : null);
  return value as DocxTracking;
}
