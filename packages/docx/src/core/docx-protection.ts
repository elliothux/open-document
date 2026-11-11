import { officePasswordUnits } from "@open-document/wasm/engine-source";

export interface DocxProtection {
  revision: number;
  protected: boolean;
  passwordRequired: boolean;
  reason: string;
}
export function checkDocxProtection(enabled: unknown, password: unknown): void {
  if (
    typeof enabled !== "boolean" ||
    typeof password !== "string" ||
    password.length > officePasswordUnits ||
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
