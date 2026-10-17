import { record } from "./validation.js";

export type PptxSlideEdit =
  | { action: "sectionAdd"; name: string }
  | { action: "sectionRename"; id: string; name: string }
  | { action: "sectionRemove"; id: string }
  | { action: "sectionRemoveAll" }
  | { action: "sectionDelete"; id: string }
  | { action: "sectionMove"; id: string; index: number }
  | { action: "add" }
  | { action: "copy" }
  | { action: "delete" }
  | { action: "move"; index: number }
  | { action: "hidden"; hidden: boolean }
  | { action: "background"; value: string | null }
  | { action: "size"; width: number; height: number };

export function checkPptxSlideEdit(value: unknown): void {
  const change = record(value);
  if (
    typeof change.action === "string" &&
    [
      "sectionAdd",
      "sectionRename",
      "sectionRemove",
      "sectionDelete",
      "sectionMove",
    ].includes(change.action)
  ) {
    if (change.action === "sectionAdd" || change.action === "sectionRename")
      sectionName(change.name, true);
    if (
      change.action !== "sectionAdd" &&
      (typeof change.id !== "string" || !sectionGuid.test(change.id))
    )
      throw new Error("Invalid section identity");
    if (
      change.action === "sectionMove" &&
      (!Number.isInteger(change.index) ||
        Number(change.index) < 0 ||
        Number(change.index) >= 256)
    )
      throw new Error("Invalid section position");
    return;
  }
  if (change.action === "size") {
    if (
      ![change.width, change.height].every(
        (value) =>
          typeof value === "number" &&
          Number.isFinite(value) &&
          value >= 1 &&
          value <= 14400,
      )
    )
      throw new Error("Invalid slide size");
    return;
  }
  if (change.action === "background") {
    if (
      change.value !== null &&
      (typeof change.value !== "string" || !/^[0-9a-f]{6}$/i.test(change.value))
    )
      throw new Error("Invalid slide background");
    return;
  }
  if (
    typeof change.action === "string" &&
    ["add", "copy", "delete", "sectionRemoveAll"].includes(change.action)
  )
    return;
  if (
    change.action === "move" &&
    typeof change.index === "number" &&
    Number.isInteger(change.index) &&
    change.index >= 0 &&
    change.index < 256
  )
    return;
  if (change.action === "hidden" && typeof change.hidden === "boolean") return;
  throw new Error("Invalid slide edit");
}

export interface PptxSection {
  id: string;
  name: string;
  slides: string[];
}
export interface PptxSections {
  items: PptxSection[];
  reason: string;
}
const sectionGuid =
  /^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$/iu;
function sectionName(value: unknown, required: boolean): void {
  if (
    typeof value !== "string" ||
    value.length > 255 ||
    !value.isWellFormed() ||
    (required && !value.trim()) ||
    Array.from(value).some((c) => {
      const n = c.codePointAt(0)!;
      return (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535;
    })
  )
    throw new Error("Invalid section name");
}
export function pptxSections(value: unknown, slides: string[]): PptxSections {
  const result = record(value);
  if (
    typeof result.reason !== "string" ||
    !Array.isArray(result.items) ||
    result.items.length > 256
  )
    throw new Error("Invalid section query");
  const ids = new Set<string>();
  let previous = -1;
  for (const item of result.items) {
    const section = record(item);
    if (
      typeof section.id !== "string" ||
      !sectionGuid.test(section.id) ||
      ids.has(section.id.toUpperCase()) ||
      !Array.isArray(section.slides) ||
      section.slides.length > 256
    )
      throw new Error("Invalid section query identity or slides");
    ids.add(section.id.toUpperCase());
    sectionName(section.name, false);
    for (const id of section.slides) {
      const index = typeof id === "string" ? slides.indexOf(id) : -1;
      if (index < 0 || (previous >= 0 && index !== previous + 1))
        throw new Error("Invalid section slide coverage");
      previous = index;
    }
  }
  if (previous >= 0 && previous !== slides.length - 1)
    throw new Error("Incomplete section slide coverage");
  return value as PptxSections;
}
