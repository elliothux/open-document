import type {
  DocxBibliographyEdit,
  DocxCitationEdit,
  DocxSourceEdit,
  DocxCaption,
  DocxIndexEdit,
  DocxTocEdit,
  DocxSectionBreak,
} from "../core/foundation.js";

export type DocxPageCommand =
  | {
      operation: "editDocxBibliography";
      revision: number;
      change: DocxBibliographyEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editDocxCitation";
      revision: number;
      change: DocxCitationEdit;
      profile: Record<string, string>;
    }
  | { operation: "docxSources"; revision: number }
  | { operation: "editDocxSource"; revision: number; change: DocxSourceEdit }
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
