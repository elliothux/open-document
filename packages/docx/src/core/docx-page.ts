import { integer, record } from "@open-document/wasm/abi/validation";
import {
  docxCaptionTextUnits,
  docxCoverSubtitleUnits,
  docxCoverTitleUnits,
  docxRunningContentItems,
  docxRunningContentUnits,
  docxRunningDistancePoints,
} from "@open-document/wasm/engine-source";

export interface DocxCoverPage {
  title: string;
  subtitle: string;
}
export type DocxSectionBreak = NonNullable<DocxPageSetup["startType"]>;

export { checkSectionBreak } from "./docx-sections.js";
const singleLineText = (value: unknown, max: number): value is string =>
  typeof value === "string" &&
  value.length <= max &&
  value.isWellFormed() &&
  Array.from(value).every((c) => {
    const n = c.codePointAt(0)!;
    return (
      n >= 32 &&
      n !== 127 &&
      n !== 8232 &&
      n !== 8233 &&
      n !== 65534 &&
      n !== 65535
    );
  });
export function checkDocxCoverPage(
  value: unknown,
): asserts value is DocxCoverPage | null {
  if (value === null) return;
  const cover = record(value);
  if (
    Object.keys(cover).length !== 2 ||
    Object.keys(cover).some((key) => key !== "title" && key !== "subtitle") ||
    !singleLineText(cover.title, docxCoverTitleUnits) ||
    !cover.title.trim() ||
    !singleLineText(cover.subtitle, docxCoverSubtitleUnits)
  )
    throw new Error("Invalid cover page title or subtitle");
}
import { checkDocxHyperlink } from "./docx-format.js";

import type { DocxSelection } from "./docx-hit.js";
import {
  checkPageNumbering,
  type DocxPageSetup,
  type DocxPageNumbering,
} from "./docx-format.js";

export type DocxRunningVariant = "default" | "first" | "even";
export function checkRunningVariant(
  value: unknown,
): asserts value is DocxRunningVariant {
  if (value !== "default" && value !== "first" && value !== "even")
    throw new Error("Invalid running area variant");
}
export function checkRunningOptions(first: unknown, even: unknown): void {
  if (typeof first !== "boolean" || typeof even !== "boolean")
    throw new Error("Invalid running options");
}
export type DocxRunningKind = "header" | "footer";
export type DocxPageField = {
  field: "PAGE" | "NUMPAGES";
  format?: Exclude<DocxPageNumbering["format"], "decimalZero">;
};
export interface DocxCaption {
  label: string;
  text: string;
  position: "before" | "after";
  format?: DocxPageField["format"];
  chapter?: { level: number; separator: string };
}
export function checkDocxCaption(value: unknown): asserts value is DocxCaption {
  const caption = record(value);
  if (
    Object.keys(caption).some(
      (key) =>
        !["label", "text", "position", "format", "chapter"].includes(key),
    ) ||
    !singleLineText(caption.text, docxCaptionTextUnits) ||
    (caption.position !== "before" && caption.position !== "after")
  )
    throw new Error("Invalid caption text or position");
  if ("chapter" in caption) {
    const chapter = record(caption.chapter);
    if (
      Object.keys(chapter).length !== 2 ||
      Object.keys(chapter).some(
        (key) => !["level", "separator"].includes(key),
      ) ||
      !integer(chapter.level, 1, 9) ||
      !singleLineText(chapter.separator, 5) ||
      chapter.separator === "" ||
      Array.from(
        typeof chapter.separator === "string" ? chapter.separator : "",
      ).some((c) => {
        const code = c.codePointAt(0)!;
        return code >= 127 && code <= 159;
      })
    )
      throw new Error("Invalid caption chapter");
  }
  checkBodyField({
    field: "SEQ",
    sequence: caption.label,
    ...("format" in caption ? { format: caption.format } : {}),
  });
}
export type DocxRunningContent =
  { text: string; target?: string } | DocxPageField;
export type DocxBodyField =
  | DocxPageField
  | {
      field: "SEQ";
      sequence: string;
      format?: DocxPageField["format"];
      restart?: number;
      repeat?: boolean;
      headingLevel?: number;
      hidden?: boolean;
    }
  | {
      field: "REF";
      bookmark: string;
      hyperlink?: boolean;
      numbering?: "noContext" | "relative" | "fullContext";
      separator?: string;
      relative?: boolean;
    }
  | {
      field: "NOTEREF";
      bookmark: string;
      hyperlink?: boolean;
      relative?: boolean;
      superscript?: boolean;
    }
  | {
      field: "PAGEREF";
      bookmark: string;
      format?: Exclude<DocxPageField["format"], undefined>;
      hyperlink?: boolean;
      relative?: boolean;
    };
export interface DocxBodyPageField {
  revision: number;
  selection: DocxSelection;
  field: DocxBodyField | null;
  reason: string;
}
export function checkPageField(value: unknown): asserts value is DocxPageField {
  const item = record(value);
  if (item.field !== "PAGE" && item.field !== "NUMPAGES")
    throw new Error("Invalid body page field");
  checkRunningArea("header", "default", [value], 0);
}
export function checkBodyField(value: unknown): asserts value is DocxBodyField {
  const item = record(value);
  if (item.field === "SEQ") {
    if (
      typeof item.sequence !== "string" ||
      item.sequence.length > 40 ||
      !/^[_\p{ID_Start}][_\p{ID_Continue}]*$/u.test(item.sequence) ||
      Object.keys(item).some(
        (key) =>
          ![
            "field",
            "sequence",
            "format",
            "restart",
            "repeat",
            "headingLevel",
            "hidden",
          ].includes(key),
      ) ||
      ("repeat" in item && typeof item.repeat !== "boolean") ||
      ("hidden" in item && typeof item.hidden !== "boolean") ||
      (item.hidden === true && "format" in item) ||
      ("headingLevel" in item &&
        (!Number.isInteger(item.headingLevel) ||
          Number(item.headingLevel) < 1 ||
          Number(item.headingLevel) > 9)) ||
      ("restart" in item &&
        (!Number.isInteger(item.restart) ||
          Number(item.restart) < 0 ||
          Number(item.restart) > 2147483647 ||
          item.repeat === true))
    )
      throw new Error("Invalid sequence field identifier");
    checkPageField(
      "format" in item
        ? { field: "PAGE", format: item.format }
        : { field: "PAGE" },
    );
    return;
  }
  if (
    item.field !== "PAGEREF" &&
    item.field !== "REF" &&
    item.field !== "NOTEREF"
  )
    return checkPageField(value);
  const textReference = item.field === "REF";
  const noteReference = item.field === "NOTEREF";
  if (
    typeof item.bookmark !== "string" ||
    !/^[A-Za-z_][A-Za-z0-9_]{0,39}$/u.test(item.bookmark) ||
    Object.keys(item).some(
      (key) =>
        !(
          textReference
            ? [
                "field",
                "bookmark",
                "hyperlink",
                "numbering",
                "relative",
                "separator",
              ]
            : noteReference
              ? ["field", "bookmark", "hyperlink", "relative", "superscript"]
              : ["field", "bookmark", "format", "hyperlink", "relative"]
        ).includes(key),
    ) ||
    ("hyperlink" in item && typeof item.hyperlink !== "boolean") ||
    ("numbering" in item &&
      (typeof item.numbering !== "string" ||
        !["noContext", "relative", "fullContext"].includes(item.numbering))) ||
    ("relative" in item && typeof item.relative !== "boolean") ||
    ("superscript" in item && typeof item.superscript !== "boolean") ||
    ("separator" in item &&
      (typeof item.separator !== "string" ||
        item.separator.length > 32 ||
        item.separator.startsWith("\\") ||
        item.separator.endsWith("\\") ||
        /[\p{Cc}\p{Zl}\p{Zp}]/u.test(item.separator)))
  )
    throw new Error("Invalid page reference target");
  if (!textReference && !noteReference)
    checkPageField(
      "format" in item
        ? { field: "PAGE", format: item.format }
        : { field: "PAGE" },
    );
}
export interface DocxRunningArea {
  revision: number;
  section: number;
  linked: boolean;
  /** LF separates paragraphs; U+2028 is an inline soft break. */
  content: DocxRunningContent[];
  distance: number;
  reason: string;
  shared: boolean;
  differentFirst: boolean;
  differentEven: boolean;
}
export function checkRunningKind(
  kind: unknown,
): asserts kind is DocxRunningKind {
  if (kind !== "header" && kind !== "footer")
    throw new Error("Invalid running area kind");
}
export function checkRunningArea(
  kind: unknown,
  variant: unknown,
  content: unknown,
  distance: unknown,
): void {
  checkRunningKind(kind);
  checkRunningVariant(variant);
  if (!Array.isArray(content) || content.length > docxRunningContentItems)
    throw new Error("Invalid running content");
  let units = 0;
  for (const value of content) {
    const item = record(value);
    if (
      Object.keys(item).every((key) => key === "text" || key === "target") &&
      typeof item.text === "string" &&
      !/[\r\f\v]/u.test(item.text)
    ) {
      if ("target" in item) {
        if (typeof item.target !== "string" || !item.text)
          throw new Error("Invalid running link");
        checkDocxHyperlink(item.target);
      }
      units += item.text.length;
    } else if (
      (item.field === "PAGE" || item.field === "NUMPAGES") &&
      Object.keys(item).every((key) => ["field", "format"].includes(key))
    ) {
      if ("format" in item) {
        checkPageNumbering({ start: 1, format: item.format });
        if (item.format === "decimalZero")
          throw new Error("Invalid explicit running field format");
      }
      units++;
    } else throw new Error("Invalid running content item");
  }
  if (
    units > docxRunningContentUnits ||
    typeof distance !== "number" ||
    !Number.isFinite(distance) ||
    distance < 0 ||
    distance > docxRunningDistancePoints ||
    !Number.isInteger(distance * 20)
  )
    throw new Error("Invalid running content or distance");
}
