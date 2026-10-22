import { record } from "./validation.js";

export interface XlsxDrawingClipboard {
  fragment: string;
  text: string;
}

export function checkDrawingFragment(value: unknown): asserts value is string {
  if (
    typeof value !== "string" ||
    !value ||
    value.length > 4194304 ||
    !value.isWellFormed()
  )
    throw new Error("Invalid drawing clipboard fragment");
}

export function drawingClipboard(value: unknown): XlsxDrawingClipboard {
  const result = record(value);
  checkDrawingFragment(result.fragment);
  if (
    typeof result.text !== "string" ||
    result.text.length > 32767 ||
    !result.text.isWellFormed() ||
    Object.keys(result).length !== 2
  )
    throw new Error("Invalid drawing clipboard result");
  return { fragment: result.fragment, text: result.text };
}

export function drawingFragmentImage(value: unknown): Uint8Array | null {
  const result = record(value);
  if (Object.keys(result).length !== 1 || !("bytes" in result))
    throw new Error("Invalid drawing clipboard image");
  if (result.bytes === null) return null;
  if (typeof result.bytes !== "string" || result.bytes.length > 2796204)
    throw new Error("Invalid drawing clipboard image");
  const bytes = Uint8Array.from(atob(result.bytes), (char) =>
    char.charCodeAt(0),
  );
  if (bytes.length > 2097152)
    throw new Error("Drawing clipboard image exceeds 2MiB");
  return bytes;
}
