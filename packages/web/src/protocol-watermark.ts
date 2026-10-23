import type { DocxWatermark } from "@open-document/wasm/foundation";
export type DocxWatermarkRequest =
  | { operation: "watermark"; revision: number }
  | {
      operation: "setWatermark";
      revision: number;
      value: DocxWatermark | null;
      profile: Record<string, string>;
    };
