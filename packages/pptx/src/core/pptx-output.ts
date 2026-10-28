import type { DrawingBatch } from "@open-document/wasm/abi/drawing";
import { drawingBatch } from "@open-document/wasm/abi/drawing";
import { integer, record } from "@open-document/wasm/abi/validation";

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
  | { operation: "imageBytesPptx" | "mediaBytesPptx"; key: string }
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
