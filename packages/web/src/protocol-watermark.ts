import type { DocxWatermark } from "@open-document/wasm/foundation";
export type DocxWatermarkRequest =
  | { operation: "watermark"; revision: number; section: number }
  | {
      operation: "setWatermark";
      revision: number;
      section: number;
      value: DocxWatermark | null;
      profile: Record<string, string>;
    };
