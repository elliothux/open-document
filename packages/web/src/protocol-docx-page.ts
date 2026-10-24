import type { DocxCaption, DocxTocEdit } from "@open-document/wasm/foundation";

export type DocxPageCommand =
  | { operation: "docxTableOfContents"; revision: number }
  | {
      operation: "editDocxTableOfContents";
      revision: number;
      change: DocxTocEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "insertDocxCaption";
      revision: number;
      caption: DocxCaption;
      profile: Record<string, string>;
    };
