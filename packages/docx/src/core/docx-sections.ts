import type { DocxFlow } from "./preview.js";
import { record } from "@open-document/wasm/abi/validation";

type SectionStart = "nextPage" | "oddPage" | "evenPage" | "continuous";

export function checkSectionBreak(
  value: unknown,
): asserts value is SectionStart {
  if (
    value !== "nextPage" &&
    value !== "oddPage" &&
    value !== "evenPage" &&
    value !== "continuous"
  )
    throw new Error("Invalid section break type");
}

export interface DocxPageSetup {
  section: number;
  /** Omission retains the native section start type; queries always include it. */
  startType?: SectionStart;
  /** Omission retains the section's native placement and document inheritance. */
  footnotesAt?: "pageBottom" | "beneathText";
  width: number;
  height: number;
  top: number;
  right: number;
  bottom: number;
  left: number;
  /** Rotates dimensions and margins in core when the requested orientation differs. */
  orientation?: "portrait" | "landscape";
}

export function checkPageSection(value: unknown): asserts value is number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0 ||
    value >= 1024
  )
    throw new Error("Invalid DOCX page section");
}

export function checkPageSetup(value: unknown): void {
  const page = record(value);
  checkPageSection(page.section);
  if ("startType" in page) checkSectionBreak(page.startType);
  if (
    "footnotesAt" in page &&
    page.footnotesAt !== "pageBottom" &&
    page.footnotesAt !== "beneathText"
  )
    throw new Error("Invalid footnote placement");
  const fields = ["width", "height", "top", "right", "bottom", "left"];
  if (
    !Object.keys(page).every(
      (key) =>
        fields.includes(key) ||
        key === "orientation" ||
        key === "section" ||
        key === "startType" ||
        key === "footnotesAt",
    ) ||
    (page.orientation !== undefined &&
      page.orientation !== "portrait" &&
      page.orientation !== "landscape") ||
    !fields.every(
      (key) =>
        typeof page[key] === "number" &&
        Number.isFinite(page[key]) &&
        Number(page[key]) >= 0 &&
        Number(page[key]) <= 14400 &&
        Number.isInteger(Number(page[key]) * 20),
    ) ||
    Number(page.width) < 36 ||
    Number(page.height) < 36 ||
    Number(page.width) - Number(page.left) - Number(page.right) < 12 ||
    Number(page.height) - Number(page.top) - Number(page.bottom) < 12
  )
    throw new Error("Invalid DOCX page dimensions or margins");
}

export type DocxSectionBreak = {
  beforeParagraph: number;
  beforeTable: number;
  kind: "nextPage" | "oddPage" | "evenPage" | "continuous";
  restartNumbering: boolean;
} & Pick<
  DocxFlow,
  | "page"
  | "pageBorders"
  | "pageNumbering"
  | "footnotesAt"
  | "columns"
  | "headers"
  | "headerDistance"
  | "footers"
  | "footerDistance"
  | "differentFirst"
  | "differentEven"
>;

export function checkDocxSections(
  flow: Record<string, unknown>,
  paragraphCount: number,
  checkFlow: (value: unknown) => DocxFlow,
): void {
  if (flow.endnotesAt !== "sectEnd" && flow.endnotesAt !== "docEnd")
    throw new Error("Invalid endnote placement");
  if (flow.footnotesAt !== "pageBottom" && flow.footnotesAt !== "beneathText")
    throw new Error("Invalid footnote placement");
  if (
    !Array.isArray(flow.sectionBreaks) ||
    flow.sectionBreaks.length >= 1024 ||
    !Array.isArray(flow.tables)
  )
    throw new Error("Invalid document sections");
  let previousParagraph = 0;
  let previousTable = 0;
  for (const value of flow.sectionBreaks) {
    const section = record(value);
    if (
      typeof section.beforeParagraph !== "number" ||
      !Number.isSafeInteger(section.beforeParagraph) ||
      section.beforeParagraph <= previousParagraph ||
      section.beforeParagraph > paragraphCount ||
      typeof section.beforeTable !== "number" ||
      !Number.isSafeInteger(section.beforeTable) ||
      section.beforeTable < previousTable ||
      section.beforeTable > flow.tables.length ||
      typeof section.kind !== "string" ||
      !["nextPage", "oddPage", "evenPage", "continuous"].includes(
        section.kind,
      ) ||
      (section.footnotesAt !== "pageBottom" &&
        section.footnotesAt !== "beneathText") ||
      typeof section.restartNumbering !== "boolean"
    )
      throw new Error("Invalid document section boundary");
    if (
      (section.beforeTable > 0 &&
        Number(record(flow.tables[section.beforeTable - 1]).beforeParagraph) >=
          section.beforeParagraph) ||
      (section.beforeTable < flow.tables.length &&
        Number(record(flow.tables[section.beforeTable]).beforeParagraph) <
          section.beforeParagraph)
    )
      throw new Error("Invalid document section table boundary");
    previousParagraph = section.beforeParagraph;
    previousTable = section.beforeTable;
    checkFlow({
      ...flow,
      ...section,
      sectionBreaks: [],
      paragraphs: [],
      tables: [],
      notes: [],
    });
  }
}
