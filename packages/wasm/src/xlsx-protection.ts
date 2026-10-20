import { record } from "./validation.js";
import { encodeBytes } from "./session.js";
import type { XlsxSheetEdit } from "./xlsx-sheet.js";

export interface XlsxProtection {
  protected: boolean;
  passwordRequired: boolean;
  reason: string;
}

export function xlsxProtection(value: unknown): XlsxProtection {
  const fields = record(value);
  if (
    typeof fields.protected !== "boolean" ||
    typeof fields.passwordRequired !== "boolean" ||
    typeof fields.reason !== "string"
  )
    throw new Error("Invalid protection state");
  return value as XlsxProtection;
}

export function protectionSalt(change: XlsxSheetEdit): string {
  return (change.action === "protection" ||
    change.action === "workbookProtection") &&
    change.enabled &&
    change.password
    ? encodeBytes(crypto.getRandomValues(new Uint8Array(16)))
    : "";
}
