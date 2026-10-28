import type { DocxWatermark } from "../core/foundation.js";
export type DocxWatermarkRequest =
  | { operation: "watermark"; revision: number; section: number }
  | {
      operation: "setWatermark";
      revision: number;
      section: number;
      value: DocxWatermark | null;
      profile: Record<string, string>;
    };
