import type {
  DocxCaption,
  DocxIndexEdit,
  DocxTocEdit,
  DocxSectionBreak,
} from "@open-document/wasm/foundation";

export type DocxPageCommand =
  | { operation: "docxIndexes"; revision: number }
  | {
      operation: "editDocxIndex";
      revision: number;
      change: DocxIndexEdit;
      profile: Record<string, string>;
    }
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
