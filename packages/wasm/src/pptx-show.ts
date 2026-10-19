import { drawingBatch, type DrawingBatch } from "./drawing.js";
import { integer, record } from "./validation.js";
import { pptxHyperlink } from "./pptx-objects.js";
import { checkPptxShowInk, type PptxShowInkChange } from "./pptx-show-ink.js";
export type { PptxShowInkChange } from "./pptx-show-ink.js";

export type PptxShowAction =
  | "start"
  | "startSettings"
  | "followLink"
  | "end"
  | "next"
  | "previous"
  | "first"
  | "last"
  | "goto"
  | "gotoPosition"
  | "pause"
  | "tick"
  | "click"
  | "resume";
export interface PptxShowState {
  active: boolean;
  external: string | null;
  paused: boolean;
  step: number;
  steps: number;
  revision: number;
  slide: string | null;
  index: number;
  count: number;
  order: string[];
  position: number;
  custom: string | null;
  text: string;
  nextSlide: string | null;
  notes: { text: string; reason: string };
  ink: { strokes: number; points: number; drawing: boolean };
}
export interface PptxShowLayout extends DrawingBatch {
  links: {
    id: string;
    label: string;
    reason: string;
    external: string | null;
  }[];
  animating: boolean;
  id: number;
  revision: number;
}
export type PptxShowCommand =
  | { operation: "imageKeysShowPptx" }
  | {
      operation: "inkShowPptx";
      revision: number;
      layoutId: number;
      time: number;
      change: PptxShowInkChange;
    }
  | {
      operation: "controlShowPptx";
      revision: number;
      action: PptxShowAction;
      time: number;
      slide: string;
      custom?: string;
      layoutId?: number;
      x?: number;
      y?: number;
    }
  | {
      operation: "layoutShowPptx";
      time: number;
      revision: number;
      profile: Record<string, string>;
    };

export function checkPptxShow(command: PptxShowCommand): void {
  if (command.operation === "imageKeysShowPptx") return;
  if (
    !["controlShowPptx", "layoutShowPptx", "inkShowPptx"].includes(
      command.operation,
    )
  )
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
  if (command.operation === "inkShowPptx") {
    if (!integer(command.layoutId, 1, 0x7fffffff))
      throw new Error("Invalid ink frame identity");
    checkPptxShowInk(command.change);
  }
  if (
    command.operation === "controlShowPptx" &&
    (![
      "start",
      "startSettings",
      "followLink",
      "end",
      "next",
      "previous",
      "first",
      "last",
      "goto",
      "gotoPosition",
      "pause",
      "tick",
      "click",
      "resume",
    ].includes(command.action) ||
      typeof command.slide !== "string" ||
      command.slide.length > 1024 ||
      (!["start", "goto", "gotoPosition", "followLink"].includes(
        command.action,
      ) &&
        command.slide !== "") ||
      (["goto", "gotoPosition", "followLink"].includes(command.action) &&
        command.slide === "") ||
      (command.action === "gotoPosition" &&
        (!integer(Number(command.slide), 0, 255) ||
          String(Number(command.slide)) !== command.slide)) ||
      (command.custom !== undefined &&
        (command.action !== "start" ||
          command.slide !== "" ||
          typeof command.custom !== "string" ||
          String(Number(command.custom)) !== command.custom ||
          !integer(Number(command.custom), 0, 4294967295))))
  )
    throw new Error("Invalid slideshow action or target");
  if (command.operation === "controlShowPptx") {
    const point = command.x !== undefined || command.y !== undefined;
    if (
      (command.action === "followLink" &&
        (!integer(Number(command.slide), 0, 4095) ||
          String(Number(command.slide)) !== command.slide ||
          !integer(command.layoutId, 1, 0x7fffffff))) ||
      (command.layoutId !== undefined &&
        (!integer(command.layoutId, 1, 0x7fffffff) ||
          (command.action !== "followLink" && !point))) ||
      (point &&
        (command.action !== "click" ||
          command.layoutId === undefined ||
          ![command.x, command.y].every(
            (value) =>
              typeof value === "number" &&
              Number.isFinite(value) &&
              value >= 0 &&
              value <= 14400,
          )))
    )
      throw new Error("Invalid slideshow interaction");
  }
}
export function pptxShowState(value: unknown): void {
  const state = record(value),
    notes = record(state.notes),
    ink = record(state.ink);
  if (
    typeof state.active !== "boolean" ||
    typeof state.paused !== "boolean" ||
    !integer(ink.strokes, 0, 256) ||
    !integer(ink.points, 0, 32768) ||
    typeof ink.drawing !== "boolean" ||
    (!state.active && (ink.strokes !== 0 || ink.points !== 0 || ink.drawing)) ||
    !integer(state.steps, 0, 128) ||
    !integer(state.step, 0, Number(state.steps)) ||
    !integer(state.revision, 0, 0x7fffffff) ||
    !integer(state.count, 1, 256) ||
    !integer(state.index, -1, Number(state.count) - 1) ||
    !Array.isArray(state.order) ||
    state.order.length > 256 ||
    !state.order.every(
      (id: unknown) =>
        typeof id === "string" &&
        id.length > 0 &&
        id.length <= 1024 &&
        id.isWellFormed(),
    ) ||
    !integer(state.position, -1, state.order.length - 1) ||
    (!state.active && state.external !== null) ||
    (state.custom !== null &&
      (typeof state.custom !== "string" ||
        String(Number(state.custom)) !== state.custom ||
        !integer(Number(state.custom), 0, 4294967295))) ||
    (state.active
      ? Number(state.position) < 0 ||
        state.order[Number(state.position)] !== state.slide
      : state.order.length !== 0 ||
        state.position !== -1 ||
        state.custom !== null) ||
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
  if (state.external !== null)
    pptxHyperlink({ kind: "external", target: state.external });
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
  if (!Array.isArray(layout.links) || layout.links.length > 4096)
    throw new Error("Invalid slideshow links");
  const ids = new Set<string>();
  let units = 0;
  for (const item of layout.links) {
    const link = record(item);
    if (
      typeof link.id !== "string" ||
      String(Number(link.id)) !== link.id ||
      !integer(Number(link.id), 0, 4095) ||
      ids.has(link.id) ||
      typeof link.label !== "string" ||
      !link.label ||
      link.label.length > 1024 ||
      !link.label.isWellFormed() ||
      typeof link.reason !== "string" ||
      link.reason.length > 8192 ||
      Object.keys(link).length !== 4 ||
      Object.keys(link).some(
        (key) => !["id", "label", "reason", "external"].includes(key),
      )
    )
      throw new Error("Invalid slideshow link");
    if (link.external !== null)
      pptxHyperlink({ kind: "external", target: link.external });
    ids.add(link.id);
    units +=
      link.label.length +
      link.reason.length +
      (typeof link.external === "string" ? link.external.length : 0);
  }
  if (units > 1048576) throw new Error("Slideshow links exceed budget");
}
