import { docxMarkupSourceUnits } from "@open-document/wasm/engine-source";
import { type DocxTableClipboard } from "./docx-table.js";
export type DocxClipboard = DocxTableClipboard & { kind: "body" | "cells" };
export type DocxPasteMode = "source" | "merge" | "text";
export function checkDocxPasteMode(
  mode: unknown,
): asserts mode is DocxPasteMode {
  if (mode !== "source" && mode !== "merge" && mode !== "text")
    throw new Error("Unknown markup paste mode");
}
export function checkMarkdown(
  markdown: string,
  maxUnits = docxMarkupSourceUnits,
): void {
  if (
    typeof markdown !== "string" ||
    !markdown.trim() ||
    markdown.length > maxUnits
  )
    throw new Error(`Markdown requires 1..${maxUnits} source units`);
}
export function checkHtml(
  html: string,
  maxUnits = docxMarkupSourceUnits,
): void {
  if (typeof html !== "string" || !html.trim() || html.length > maxUnits)
    throw new Error(`HTML requires 1..${maxUnits} source units`);
}
