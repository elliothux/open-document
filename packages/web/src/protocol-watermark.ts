import type { DocxTextWatermark } from "@open-document/wasm/foundation";
export type DocxWatermarkRequest =
  | { operation: "textWatermark"; revision: number }
  | {
      operation: "setTextWatermark";
      revision: number;
      value: DocxTextWatermark | null;
      profile: Record<string, string>;
    };
