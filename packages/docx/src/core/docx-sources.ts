import { integer, record } from "@open-document/wasm/abi/validation";
import {
  docxBibliographyHeadingUnits,
  docxSourceAuthorUnits,
  docxSourcePublisherUnits,
  docxSourceTagUnits,
  docxSourceTitleUnits,
  docxSourceUrlUnits,
  docxSourceYearUnits,
} from "@open-document/wasm/engine-source";

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
      ? !plain(change.title, docxBibliographyHeadingUnits) ||
        !change.title.trim()
      : typeof change.action !== "string" ||
        !["update", "delete"].includes(change.action) ||
        !integer(change.paragraph, 0, 2147483647))
  )
    throw new Error("Invalid bibliography command");
}

const limits = {
  author: docxSourceAuthorUnits,
  title: docxSourceTitleUnits,
  year: docxSourceYearUnits,
  publisher: docxSourcePublisherUnits,
  url: docxSourceUrlUnits,
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
    plain(value, docxSourceTagUnits) &&
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
