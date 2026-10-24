import type {
  DocxCaption,
  DocxTocEdit,
  DocxSectionBreak,
} from "@open-document/wasm/foundation";

export type DocxPageCommand =
  | {
      operation: "insertSectionBreak";
      revision: number;
      kind: DocxSectionBreak;
      profile: Record<string, string>;
    }
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
