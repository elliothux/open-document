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
  | { operation: "prepareImagePptx"; key: string; preview?: string }
  | { operation: "mediaBytesPptx"; key: string }
  | { operation: "imageKeysPptx"; all: boolean; hidden: boolean }
  | { operation: "previewKeysPptx"; revision: number; slide: string }
  | {
      operation: "previewPptx";
      revision: number;
      slide: string;
      profile: Record<string, string>;
    }
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
