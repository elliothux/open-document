import { integer, record } from "./validation.js";

export const sourceKinds = [
  "Book",
  "JournalArticle",
  "InternetSite",
  "Report",
  "Misc",
] as const;

export interface DocxSource {
  tag: string;
  kind: (typeof sourceKinds)[number];
  author: string;
  title: string;
  year: string;
  publisher: string;
  url: string;
}

export type DocxSourceEdit =
  | { action: "create" | "update"; source: DocxSource }
  | { action: "delete"; tag: string };

export type DocxCitationEdit =
  { action: "insert"; tag: string } | { action: "update" };

export function checkDocxCitationEdit(
  value: unknown,
): asserts value is DocxCitationEdit {
  const change = record(value);
  if (
    !(change.action === "update" && Object.keys(change).length === 1) &&
    !(
      change.action === "insert" &&
      Object.keys(change).length === 2 &&
      tag(change.tag)
    )
  )
    throw new Error("Invalid citation command");
}

export interface DocxSources {
  revision: number;
  bibliographies: {
    paragraph: number;
    endParagraph: number;
    instruction: string;
    reason: string;
  }[];
  sources: (Omit<DocxSource, "kind"> & {
    kind: string;
    reason: string;
    authorReason: string;
    deleteReason: string;
  })[];
}

export type DocxBibliographyEdit =
  | { action: "insert"; title: string }
  | { action: "update" | "delete"; paragraph: number };

export function checkDocxBibliographyEdit(
  value: unknown,
): asserts value is DocxBibliographyEdit {
  const change = record(value);
  if (
    Object.keys(change).length !== 2 ||
    (change.action === "insert"
      ? !plain(change.title, 255) || !change.title.trim()
      : typeof change.action !== "string" ||
        !["update", "delete"].includes(change.action) ||
        !integer(change.paragraph, 0, 2147483647))
  )
    throw new Error("Invalid bibliography command");
}

const limits = {
  tag: 64,
  kind: 64,
  author: 1024,
  title: 1024,
  year: 32,
  publisher: 512,
  url: 2048,
};

function plain(value: unknown, limit: number): value is string {
  return (
    typeof value === "string" &&
    value.length <= limit &&
    value.isWellFormed() &&
    Array.from(value).every((char) => {
      const code = char.codePointAt(0)!;
      return (
        code >= 32 &&
        !(code >= 127 && code <= 159) &&
        ![0x2028, 0x2029, 0xfffe, 0xffff].includes(code)
      );
    })
  );
}

function tag(value: unknown): value is string {
  return (
    plain(value, 64) &&
    value.length > 0 &&
    value.trim() === value &&
    !/["\\]/u.test(value)
  );
}

function sourceFields(value: Record<string, unknown>): boolean {
  return (
    Object.entries(limits).every(([key, size]) => plain(value[key], size)) &&
    tag(value.tag)
  );
}

export function checkDocxSourceEdit(
  value: unknown,
): asserts value is DocxSourceEdit {
  const change = record(value);
  if (
    Object.keys(change).length !== 2 ||
    (change.action === "delete"
      ? !tag(change.tag)
      : typeof change.action !== "string" ||
        !["create", "update"].includes(change.action))
  )
    throw new Error("Invalid bibliography source command");
  if (change.action === "delete") return;
  const source = record(change.source);
  if (
    Object.keys(source).length !== 7 ||
    !sourceFields(source) ||
    !sourceKinds.some((kind) => kind === source.kind) ||
    typeof source.title !== "string" ||
    !source.title.trim()
  )
    throw new Error("Invalid bibliography source fields");
}

export function docxSources(value: unknown): DocxSources {
  const catalog = record(value);
  if (
    !integer(catalog.revision, 0, 2147483647) ||
    !Array.isArray(catalog.sources) ||
    catalog.sources.length > 512
  )
    throw new Error("Invalid bibliography sources");
  const tags = new Set<string>();
  if (
    !Array.isArray(catalog.bibliographies) ||
    catalog.bibliographies.length > 256
  )
    throw new Error("Invalid bibliography field catalog");
  const fields = new Set<number>();
  for (const value of catalog.bibliographies) {
    const item = record(value);
    if (
      !integer(item.paragraph, 0, 2147483647) ||
      !integer(item.endParagraph, 0, 2147483647) ||
      typeof item.paragraph !== "number" ||
      fields.has(item.paragraph) ||
      !plain(item.reason, 8192) ||
      typeof item.instruction !== "string" ||
      item.instruction.length > 257 ||
      !item.instruction.isWellFormed()
    )
      throw new Error("Invalid bibliography field");
    fields.add(item.paragraph);
  }
  for (const entry of catalog.sources) {
    const source = record(entry);
    if (
      !sourceFields(source) ||
      !plain(source.reason, 2048) ||
      !plain(source.authorReason, 2048) ||
      !plain(source.deleteReason, 2048) ||
      (!source.reason && !sourceKinds.some((kind) => kind === source.kind)) ||
      typeof source.tag !== "string" ||
      tags.has(source.tag)
    )
      throw new Error("Invalid bibliography source record");
    tags.add(source.tag);
  }
  return value as DocxSources;
}
