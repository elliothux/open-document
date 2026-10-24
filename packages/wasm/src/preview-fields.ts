import { checkDocxCitationEdit } from "./docx-sources.js";

export function checkDocxSpanField(span: Record<string, unknown>): void {
  const citationField =
    typeof span.field === "string" && span.field.startsWith("CITATION:");
  if (citationField)
    checkDocxCitationEdit({
      action: "insert",
      tag: String(span.field).slice(9),
    });
  const noteField =
    typeof span.field === "string" &&
    /^NOTE:(?:footnote|endnote):[0-9]+$/u.test(span.field) &&
    span.field.split(":")[2] === String(Number(span.field.split(":")[2])) &&
    Number(span.field.split(":")[2]) <= 2147483647;
  if (
    typeof span.field !== "string" ||
    !/^(?:(?:PAGE|NUMPAGES)(?::(?:decimal|decimalZero|lowerLetter|upperLetter|lowerRoman|upperRoman))?|PAGEREF:[A-Za-z_][A-Za-z0-9_]{0,39}(?::(?:decimal|decimalZero|lowerLetter|upperLetter|lowerRoman|upperRoman))?(?::hyperlink)?(?::relative)?|NOTEREF:[A-Za-z_][A-Za-z0-9_]{0,39}(?::superscript)?(?::hyperlink)?(?::relative)?|REF:[A-Za-z_][A-Za-z0-9_]{0,39}(?::(?:number|numberRelative|numberFull))?(?::hyperlink)?(?::relative)?(?::separator=[^\p{Cc}\p{Zl}\p{Zp}]{1,32})?|STYLEREF:[1-9]|SEQ:[_\p{ID_Start}][_\p{ID_Continue}]{0,39}(?::(?:decimal|lowerLetter|upperLetter|lowerRoman|upperRoman))?(?::(?:repeat|restart=[0-9]{1,10}))?(?::heading=[1-9])?(?::hidden)?)?$/u.test(
      noteField || citationField ? "" : span.field,
    ) ||
    (span.field.startsWith("SEQ:") &&
      (span.field.split(":")[1]!.length > 40 ||
        Number(span.field.split("restart=")[1]?.split(":")[0] ?? 0) >
          2147483647 ||
        (span.field.endsWith(":hidden") &&
          /^SEQ:[^:]+:(?:decimal|lowerLetter|upperLetter|lowerRoman|upperRoman):/u.test(
            span.field,
          )))) ||
    (span.field !== "" && span.drawing !== null)
  )
    throw new Error("Invalid running field");
}
