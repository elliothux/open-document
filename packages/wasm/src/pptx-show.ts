import { drawingBatch, type DrawingBatch } from "./drawing.js";
import { integer, record } from "./validation.js";

export type PptxShowAction =
  | "start"
  | "end"
  | "next"
  | "previous"
  | "first"
  | "last"
  | "goto"
  | "pause"
  | "tick"
  | "click"
  | "resume";
export interface PptxShowState {
  active: boolean;
  paused: boolean;
  step: number;
  steps: number;
  revision: number;
  slide: string | null;
  index: number;
  count: number;
  text: string;
  nextSlide: string | null;
  notes: { text: string; reason: string };
}
export interface PptxShowLayout extends DrawingBatch {
  animating: boolean;
  id: number;
  revision: number;
}
export type PptxShowCommand =
  | { operation: "imageKeysShowPptx" }
  | {
      operation: "controlShowPptx";
      revision: number;
      action: PptxShowAction;
      time: number;
      slide: string;
    }
  | {
      operation: "layoutShowPptx";
      time: number;
      revision: number;
      profile: Record<string, string>;
    };

export function checkPptxShow(command: PptxShowCommand): void {
  if (command.operation === "imageKeysShowPptx") return;
  if (!["controlShowPptx", "layoutShowPptx"].includes(command.operation))
    throw new Error("Unknown slideshow command");
  if (!integer(command.revision, 0, 0x7fffffff))
    throw new Error("Invalid slideshow revision");
  if (
    typeof command.time !== "number" ||
    !Number.isFinite(command.time) ||
    command.time < 0 ||
    command.time > 1000000000
  )
    throw new Error("Invalid slideshow time");
  if (
    command.operation === "controlShowPptx" &&
    (![
      "start",
      "end",
      "next",
      "previous",
      "first",
      "last",
      "goto",
      "pause",
      "tick",
      "click",
      "resume",
    ].includes(command.action) ||
      typeof command.slide !== "string" ||
      command.slide.length > 1024 ||
      (!["start", "goto"].includes(command.action) && command.slide !== "") ||
      (command.action === "goto" && command.slide === ""))
  )
    throw new Error("Invalid slideshow action or target");
}
export function pptxShowState(value: unknown): void {
  const state = record(value),
    notes = record(state.notes);
  if (
    typeof state.active !== "boolean" ||
    typeof state.paused !== "boolean" ||
    !integer(state.steps, 0, 128) ||
    !integer(state.step, 0, Number(state.steps)) ||
    !integer(state.revision, 0, 0x7fffffff) ||
    !integer(state.count, 1, 256) ||
    !integer(state.index, -1, Number(state.count) - 1) ||
    ![state.slide, state.nextSlide].every(
      (id) =>
        id === null ||
        (typeof id === "string" && id.length > 0 && id.length <= 1024),
    ) ||
    (state.active
      ? state.slide === null || Number(state.index) < 0
      : state.slide !== null ||
        state.nextSlide !== null ||
        state.index !== -1 ||
        state.step !== 0 ||
        state.steps !== 0) ||
    typeof notes.text !== "string" ||
    notes.text.length > 32767 ||
    typeof notes.reason !== "string" ||
    notes.reason.length > 8192
  )
    throw new Error("Invalid slideshow state");
  if (typeof state.text !== "string" || state.text.length > 1048576)
    throw new Error("Invalid slideshow text");
}
export function pptxShowLayout(value: unknown): void {
  drawingBatch(value);
  const layout = record(value);
  if (
    !integer(layout.id, 1, 0x7fffffff) ||
    typeof layout.animating !== "boolean" ||
    !integer(layout.revision, 0, 0x7fffffff) ||
    !Array.isArray(layout.regions) ||
    layout.regions.length < 1 ||
    layout.regions.length > 2
  )
    throw new Error("Invalid slideshow layout");
}
