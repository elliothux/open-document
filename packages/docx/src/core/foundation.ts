export * from "./docx-chart.js";
export { type ChartSettings } from "@open-document/wasm/abi/chart";

export * from "./docx-ink.js";
export * from "./docx-tracking.js";
export * from "./docx-clipboard.js";
export * from "./docx-toc.js";
export * from "./docx-index.js";
export * from "./docx-sources.js";
export * from "./docx-protection.js";
export {
  checkRunningArea,
  checkRunningKind,
  checkRunningVariant,
  checkRunningOptions,
  checkDocxCoverPage,
  checkDocxCaption,
  type DocxCaption,
  type DocxCoverPage,
  type DocxSectionBreak,
  checkSectionBreak,
  type DocxRunningArea,
  type DocxRunningContent,
  type DocxPageField,
  type DocxBodyField,
  checkBodyField,
  checkPageField,
  type DocxBodyPageField,
  type DocxRunningKind,
  type DocxRunningVariant,
} from "./docx-page.js";
export * from "./docx-watermark.js";
import { type EditState } from "./docx-format.js";
export {
  checkDocxComment,
  type DocxCommentNavigation,
  type DocxCommentEdit,
  type DocxComments,
} from "./docx-comments.js";
export * from "./docx-format.js";
export * from "./docx-ruler.js";
export * from "./docx-picture.js";
export * from "./docx-shape.js";
export * from "./docx-math.js";

export * from "./docx-overview.js";
export {
  checkDocxRevisionEdit,
  type DocxRevisions,
  type DocxRevisionEdit,
} from "./docx-revisions.js";

export * from "./docx-list.js";
export * from "./docx-list-level.js";

export { DocumentError } from "@open-document/wasm/abi/session";

export * from "./docx-table.js";

export * from "./docx-theme.js";
/** Logical soft line break; DOCX serializes it as w:br, while LF creates a paragraph. */
export const DOCX_SOFT_BREAK = "\u2028";
/** Logical page break; serialized as w:br w:type="page", never as an XML control character. */
export const DOCX_PAGE_BREAK = "\u000c";
/** Logical column break; serialized as w:br w:type="column". */
export const DOCX_COLUMN_BREAK = "\u000b";

export {
  checkFindOptions,
  type DocxFindOptions,
  type DocxSearchResult,
} from "./docx-search.js";

export type { Budget } from "@open-document/wasm/abi/validation";

export type { DocxPosition, DocxSelection } from "./docx-hit.js";

import type { DocxHit, DocxSelectionView } from "./docx-hit.js";
export { type DocxHit } from "./docx-hit.js";

export { type DocxSelectionGeometry } from "./docx-hit.js";

export type NavigationDirection =
  "left" | "right" | "up" | "down" | "home" | "end";

export interface DocxNavigation {
  state: EditState & { selectionView?: DocxSelectionView };
  caret: DocxHit;
}

export interface DocxQuery {
  revision: number;
  compositionId: number | null;
  mainPart: string;
  texts: { id: number; paragraph: number; run: number; text: string }[];
  relationships: {
    owner: string;
    id: string;
    type: string;
    target: string;
    external: boolean;
  }[];
  diagnostics: string[];
  decodedBytes: number;
}

export type { ShapeBatch } from "@open-document/wasm/abi/shape";

export {
  noteNumberFormats,
  docxNoteNumbering,
  checkNoteNumbering,
  type DocxNoteNumbering,
  type DocxNoteNumberingValue,
  checkEndnotePosition,
  type DocxEndnotePosition,
  checkDocxNoteEdit,
  checkDocxNoteCreate,
  checkDocxNoteIdentity,
  type DocxNotes,
  type DocxNoteKind,
  type DocxNoteEdit,
  type DocxNoteCreate,
  type DocxNoteIdentity,
} from "./docx-notes.js";

export { FoundationSession } from "./docx-session.js";
export type { DocxCommand, DocxResult } from "./docx-command.js";
export { checkDocxByteInput, type DocxInputLimits } from "./docx-input.js";
