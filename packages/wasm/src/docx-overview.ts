import { integer, record } from "./validation.js";

export interface DocxOverview {
  revision: number;
  headings: {
    paragraph: number;
    level: number;
    text: string;
    reason: string;
  }[];
  truncated: boolean;
  diagnostics: string[];
  /** Committed body text; Unicode scalar characters, whitespace-separated words. */
  statistics: {
    words: number;
    characters: number;
    charactersNoSpaces: number;
    paragraphs: number;
    reason: string;
  };
}

export function docxOverview(value: unknown): DocxOverview {
  const result = record(value),
    stats = record(result.statistics);
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.truncated !== "boolean" ||
    !Array.isArray(result.headings) ||
    result.headings.length > 4096 ||
    !Array.isArray(result.diagnostics) ||
    result.diagnostics.length > 4096 ||
    !result.diagnostics.every(
      (v) => typeof v === "string" && v.length <= 8192,
    ) ||
    typeof stats.reason !== "string" ||
    ![
      stats.words,
      stats.characters,
      stats.charactersNoSpaces,
      stats.paragraphs,
    ].every((v) => integer(v, 0, 1048576)) ||
    Number(stats.charactersNoSpaces) > Number(stats.characters) ||
    Number(stats.words) > Number(stats.charactersNoSpaces) ||
    Number(stats.paragraphs) > Number(stats.words)
  )
    throw new Error("Invalid DOCX overview");
  const seen = new Set<number>();
  for (const value of result.headings) {
    const heading = record(value);
    if (
      !integer(heading.paragraph, 0, 2147483647) ||
      seen.has(Number(heading.paragraph)) ||
      !integer(heading.level, 1, 9) ||
      typeof heading.text !== "string" ||
      !heading.text ||
      heading.text.length > 256 ||
      !heading.text.isWellFormed() ||
      typeof heading.reason !== "string"
    )
      throw new Error("Invalid DOCX heading");
    seen.add(Number(heading.paragraph));
  }
  return value as DocxOverview;
}
