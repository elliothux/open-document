import { type EditState } from "./docx-format.js";
import { type DrawingBatch } from "@open-document/wasm/abi/drawing";
import {
  type DocxInkStroke,
  checkInkTarget,
  checkInkPoint,
  checkInkStroke,
} from "./docx-ink.js";
import type { DocxRuntime } from "./docx-session.js";
export const docxInkCommands = {
  previewInk(
    session: DocxRuntime,
    {
      revision,
      layoutId,
      page,
      stroke,
    }: {
      revision: number;
      layoutId: number;
      page: number;
      stroke: DocxInkStroke;
    },
  ) {
    checkInkTarget(revision, layoutId, page);
    checkInkStroke(stroke, () => session.inputLimits().inkPoints);
    return session.call<DrawingBatch>({
      operation: "docxInk",
      action: "preview",
      revision,
      layoutId,
      page,
      stroke,
    });
  },
  insertInk(
    session: DocxRuntime,
    {
      revision,
      layoutId,
      page,
      stroke,
      profile = {},
    }: {
      revision: number;
      layoutId: number;
      page: number;
      stroke: DocxInkStroke;
      profile?: Record<string, string> | undefined;
    },
  ) {
    checkInkTarget(revision, layoutId, page);
    checkInkStroke(stroke, () => session.inputLimits().inkPoints);
    return session.call<EditState>({
      operation: "docxInk",
      action: "insert",
      revision,
      layoutId,
      page,
      stroke,
      profile,
    });
  },
  eraseInk(
    session: DocxRuntime,
    {
      revision,
      layoutId,
      page,
      x,
      y,
    }: {
      revision: number;
      layoutId: number;
      page: number;
      x: number;
      y: number;
    },
  ) {
    checkInkTarget(revision, layoutId, page);
    checkInkPoint(x, y);
    return session.call<EditState>({
      operation: "docxInk",
      action: "erase",
      revision,
      layoutId,
      page,
      x,
      y,
    });
  },
};
