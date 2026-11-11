import {
  pptxFooterParagraphCount,
  pptxFooterTextUnits,
} from "@open-document/wasm/engine-source";
import { record } from "@open-document/wasm/abi/validation";

export interface PptxFooterContent {
  date:
    string | { format: number; language: "en-US" | "zh-CN" | "zh-TW" } | null;
  footer: string | null;
  number: boolean;
}
export interface PptxFooter extends PptxFooterContent {
  reason: string;
}

export function checkPptxFooterContent(value: unknown): void {
  const content = record(value);
  if (
    Object.keys(content).length !== 3 ||
    Object.keys(content).some(
      (key) => !["date", "footer", "number"].includes(key),
    )
  )
    throw new Error("Invalid slide footer content");
  if (typeof content.number !== "boolean")
    throw new Error("Invalid slide numbering flag");
  const date = content.date;
  if (date !== null && typeof date !== "string") {
    const settings = record(date);
    if (
      Object.keys(settings).length !== 2 ||
      Object.keys(settings).some(
        (key) => !["format", "language"].includes(key),
      ) ||
      typeof settings.format !== "number" ||
      !Number.isInteger(settings.format) ||
      settings.format < 1 ||
      settings.format > 13 ||
      typeof settings.language !== "string" ||
      !["en-US", "zh-CN", "zh-TW"].includes(settings.language)
    )
      throw new Error("Invalid automatic slide date");
  }
  for (const value of [
    typeof date === "string" ? date : null,
    content.footer,
  ]) {
    if (value === null) continue;
    if (
      typeof value !== "string" ||
      value.length > pptxFooterTextUnits ||
      !value.isWellFormed() ||
      value.replace(/\r\n?/g, "\n").split("\n").length >
        pptxFooterParagraphCount ||
      Array.from(value).some((c) => {
        const n = c.codePointAt(0)!;
        return (
          (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535
        );
      })
    )
      throw new Error("Invalid slide footer text");
  }
}
