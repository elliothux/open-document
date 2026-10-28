import { checkFormatPatch, type CharacterFormatPatch } from "./docx-format.js";
import { validListLevelSettings, type ListLevelSettings } from "./docx-list.js";
import { record } from "@open-document/wasm/abi/validation";

export interface DocxListLevelUpdate extends ListLevelSettings {
  left?: number | null;
  first?: number | null;
  character?: Omit<CharacterFormatPatch, "style">;
}

export function checkListLevelUpdate(
  id: number,
  level: number,
  definition: DocxListLevelUpdate,
): void {
  const fields = record(definition);
  if (
    !Number.isInteger(id) ||
    id < 1 ||
    id > 2147483646 ||
    !validListLevelSettings(fields, level) ||
    !Object.keys(fields).every((key) =>
      [
        "format",
        "pattern",
        "start",
        "restart",
        "align",
        "suffix",
        "left",
        "first",
        "character",
      ].includes(key),
    )
  )
    throw new Error("Invalid list level definition");
  const character =
    fields.character === undefined ? {} : record(fields.character);
  if ("style" in character)
    throw new Error("List markers cannot reference a character style");
  checkFormatPatch(character);
  const paragraph: Record<string, unknown> = {};
  for (const key of ["left", "first"] as const)
    if (fields[key] !== undefined) paragraph[key] = fields[key];
  checkFormatPatch(paragraph, true);
}
