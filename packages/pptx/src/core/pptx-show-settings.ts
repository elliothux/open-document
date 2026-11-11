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
export function checkPptxShowSettings(value: unknown): void {
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
        ? !integer(slides.first, 1, 256) ||
          !integer(slides.last, Number(slides.first), 256)
        : slides.kind !== "custom" ||
          typeof slides.id !== "string" ||
          String(Number(slides.id)) !== slides.id ||
          !integer(Number(slides.id), 0, 4294967295))
  )
    throw new Error("Invalid slideshow settings");
}
