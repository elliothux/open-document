import { record } from "./validation.js";

export type PptxBackgroundFill =
  | { kind: "solid"; color: string }
  | {
      kind: "linear";
      startColor: string;
      endColor: string;
      angle: number;
      scaled: boolean;
    };

export function checkPptxBackgroundFill(value: unknown): void {
  const fill = record(value);
  const colors =
    fill.kind === "solid" ? [fill.color] : [fill.startColor, fill.endColor];
  if (
    !colors.every((c) => typeof c === "string" && /^[0-9a-f]{6}$/i.test(c)) ||
    !(
      fill.kind === "solid" ||
      (fill.kind === "linear" &&
        typeof fill.angle === "number" &&
        Number.isFinite(fill.angle) &&
        fill.angle >= 0 &&
        fill.angle <= 360 &&
        typeof fill.scaled === "boolean")
    ) ||
    Object.keys(fill).some(
      (key) =>
        !(
          fill.kind === "solid"
            ? ["kind", "color"]
            : ["kind", "startColor", "endColor", "angle", "scaled"]
        ).includes(key),
    )
  )
    throw new Error("Invalid slide background fill");
}

export type PptxSlideEdit =
  | { action: "layout"; id: string }
  | { action: "resetLayout" }
  | { action: "notes"; text: string }
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
  | { action: "background"; value: PptxBackgroundFill | null }
  | { action: "size"; width: number; height: number };

export function checkPptxSlideEdit(value: unknown): void {
  const change = record(value);
  if (change.action === "resetLayout") {
    if (Object.keys(change).length !== 1)
      throw new Error("Reset layout accepts only an action");
    return;
  }
  if (change.action === "layout") {
    if (
      typeof change.id !== "string" ||
      !change.id ||
      change.id.length > 65535 ||
      !change.id.isWellFormed() ||
      Object.keys(change).some((key) => !["action", "id"].includes(key))
    )
      throw new Error("Invalid slide layout identity");
    return;
  }
  if (change.action === "notes") {
    if (
      typeof change.text !== "string" ||
      change.text.length > 32767 ||
      !change.text.isWellFormed() ||
      Array.from(change.text).some((c) => {
        const code = c.codePointAt(0)!;
        return (
          (code < 32 && ![9, 10, 13].includes(code)) ||
          code === 65534 ||
          code === 65535
        );
      })
    )
      throw new Error("Invalid slide notes");
    return;
  }
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
    if (change.value !== null) checkPptxBackgroundFill(change.value);
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

export interface PptxSlideLayouts {
  current: string;
  choices: { id: string; name: string; master: string; masterName: string }[];
  reason: string;
}

export function pptxSlideLayouts(value: unknown): PptxSlideLayouts {
  const state = record(value);
  if (
    typeof state.current !== "string" ||
    !state.current.isWellFormed() ||
    state.current.length > 65535 ||
    typeof state.reason !== "string" ||
    !Array.isArray(state.choices) ||
    state.choices.length > 256
  )
    throw new Error("Invalid slide layout catalog");
  const ids = new Set<string>();
  let units = 0;
  for (const value of state.choices) {
    const choice = record(value);
    for (const key of ["id", "name", "master", "masterName"]) {
      const text = choice[key];
      if (
        typeof text !== "string" ||
        !text.isWellFormed() ||
        text.length > (key === "name" || key === "masterName" ? 1024 : 65535)
      )
        throw new Error("Invalid slide layout entry");
      units += text.length;
    }
    if (
      typeof choice.id !== "string" ||
      typeof choice.master !== "string" ||
      !choice.id ||
      !choice.master ||
      ids.has(choice.id) ||
      units > 1048576
    )
      throw new Error("Invalid slide layout identity or budget");
    ids.add(choice.id);
  }
  if ((!state.reason || state.choices.length) && !ids.has(state.current))
    throw new Error("Missing current slide layout");
  return value as PptxSlideLayouts;
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
