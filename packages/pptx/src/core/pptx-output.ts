import type { DrawingBatch } from "@open-document/wasm/abi/drawing";

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
  | { operation: "prepareImagePptx" | "mediaBytesPptx"; key: string }
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
