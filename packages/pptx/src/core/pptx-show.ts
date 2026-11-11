import { pptxShowInkBatchPoints } from "@open-document/wasm/engine-source";
import type { DrawingBatch } from "@open-document/wasm/abi/drawing";
import { integer } from "@open-document/wasm/abi/validation";
import { checkPptxShowInk, type PptxShowInkChange } from "./pptx-show-ink.js";
export type { PptxShowInkChange } from "./pptx-show-ink.js";
import {
  checkShowMediaChange,
  type PptxShowMediaState,
  type PptxShowMediaChange,
  type PptxShowMediaDrawing,
} from "./pptx-show-media.js";
export type {
  PptxShowMediaState,
  PptxShowMediaChange,
  PptxShowMediaDrawing,
} from "./pptx-show-media.js";

export type PptxShowAction =
  | "start"
  | "startSettings"
  | "followLink"
  | "end"
  | "saveInk"
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
  media: PptxShowMediaState[];
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
  media: PptxShowMediaDrawing[];
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
  | {
      operation: "mediaShowPptx";
      revision: number;
      time: number;
      layoutId?: number;
      change: PptxShowMediaChange;
    }
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

export function checkPptxShow(
  command: PptxShowCommand,
  maxInkBatchPoints = pptxShowInkBatchPoints,
): void {
  if (command.operation === "imageKeysShowPptx") return;
  if (
    ![
      "controlShowPptx",
      "layoutShowPptx",
      "inkShowPptx",
      "mediaShowPptx",
    ].includes(command.operation)
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
    checkPptxShowInk(command.change, maxInkBatchPoints);
  }
  if (command.operation === "mediaShowPptx") {
    checkShowMediaChange(command.change);
    const feedback = ["ended", "paused", "blocked", "error"].includes(
      command.change.action,
    );
    if (
      feedback
        ? command.layoutId !== undefined
        : !integer(command.layoutId, 1, 0x7fffffff)
    )
      throw new Error("Invalid media frame binding");
  }
  if (
    command.operation === "controlShowPptx" &&
    (![
      "start",
      "startSettings",
      "followLink",
      "end",
      "saveInk",
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
