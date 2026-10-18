import type { DrawingBatch } from "./drawing.js";
import { drawingBatch } from "./drawing.js";
import { integer, record } from "./validation.js";

export interface PptxPrintLayout extends DrawingBatch {
  revision: number;
}

export interface PptxLayout extends DrawingBatch {
  id: number;
  revision: number;
  slide: string;
  diagnostics: string[];
}

export type PptxOutputCommand =
  | { operation: "imageBytesPptx"; key: string }
  | { operation: "imageKeysPptx"; all: boolean; hidden: boolean }
  | {
      operation: "printLayoutPptx";
      revision: number;
      all: boolean;
      hidden: boolean;
      profile: Record<string, string>;
    }
  | {
      operation: "exportPptxPdf";
      revision: number;
      all: boolean;
      hidden: boolean;
      profile: Record<string, string>;
      outputBytes: number;
    };

export function pptxPrintLayout(value: unknown): void {
  drawingBatch(value);
  const layout = record(value);
  if (!integer(layout.revision, 0, 0x7fffffff))
    throw new Error("Invalid presentation print layout");
}
