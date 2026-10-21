import { record } from "./validation.js";

export interface DocxProtection {
  revision: number;
  protected: boolean;
  passwordRequired: boolean;
  reason: string;
}
export function docxProtection(value: unknown): DocxProtection {
  const result = record(value);
  if (
    !Number.isSafeInteger(result.revision) ||
    Number(result.revision) < 0 ||
    typeof result.protected !== "boolean" ||
    typeof result.passwordRequired !== "boolean" ||
    typeof result.reason !== "string" ||
    Object.keys(result).length !== 4 ||
    Object.keys(result).some(
      (key) =>
        !["revision", "protected", "passwordRequired", "reason"].includes(key),
    ) ||
    (!result.protected && result.passwordRequired)
  )
    throw new Error("Invalid document protection state");
  return value as DocxProtection;
}
export function checkDocxProtection(enabled: unknown, password: unknown): void {
  if (
    typeof enabled !== "boolean" ||
    typeof password !== "string" ||
    password.length > 255 ||
    !password.isWellFormed() ||
    Array.from(password).some((character) => {
      const code = character.codePointAt(0)!;
      return (
        (code < 32 && ![9, 10, 13].includes(code)) ||
        code === 65534 ||
        code === 65535
      );
    })
  )
    throw new Error("Invalid document protection settings");
}
