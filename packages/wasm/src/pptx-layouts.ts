import { record } from "./validation.js";

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
