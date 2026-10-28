import { integer, record } from "@open-document/wasm/abi/validation";

export interface PptxShowSettings {
  slides:
    | { kind: "all" }
    | { kind: "range"; first: number; last: number }
    | { kind: "custom"; id: string };
  timings: boolean;
  animations: boolean;
  loop: boolean;
}
export function checkPptxShowSettings(value: unknown, count = 256): void {
  const settings = record(value),
    slides = record(settings.slides);
  const fields =
    slides.kind === "all"
      ? ["kind"]
      : slides.kind === "range"
        ? ["kind", "first", "last"]
        : ["kind", "id"];
  if (
    Object.keys(settings).length !== 4 ||
    Object.keys(settings).some(
      (key) => !["slides", "timings", "animations", "loop"].includes(key),
    ) ||
    [settings.timings, settings.animations, settings.loop].some(
      (value) => typeof value !== "boolean",
    ) ||
    Object.keys(slides).length !== fields.length ||
    Object.keys(slides).some((key) => !fields.includes(key)) ||
    (slides.kind === "all"
      ? false
      : slides.kind === "range"
        ? !integer(slides.first, 1, count) ||
          !integer(slides.last, Number(slides.first), count)
        : slides.kind !== "custom" ||
          typeof slides.id !== "string" ||
          String(Number(slides.id)) !== slides.id ||
          !integer(Number(slides.id), 0, 4294967295))
  )
    throw new Error("Invalid slideshow settings");
}
export function pptxShowSettingsState(value: unknown): void {
  const query = record(value),
    state = record(query.showSettings);
  if (
    typeof state.reason !== "string" ||
    state.reason.length > 8192 ||
    (state.value === null && !state.reason)
  )
    throw new Error("Invalid slideshow settings state");
  if (state.value === null) return;
  if (!Array.isArray(query.slides)) throw new Error("Missing slideshow slides");
  checkPptxShowSettings(state.value, query.slides.length);
  const selection = record(record(state.value).slides);
  if (selection.kind === "custom") {
    const shows = record(query.customShows).items;
    if (
      !Array.isArray(shows) ||
      !shows.some((show) => record(show).id === selection.id)
    )
      throw new Error("Unknown selected custom show");
  }
}
