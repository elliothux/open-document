import { record } from "@open-document/wasm/abi/validation";

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
