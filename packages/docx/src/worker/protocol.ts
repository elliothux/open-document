import type { DocxWatermarkRequest } from "./protocol-watermark.js";
import type { DocxInkRequest } from "./protocol-docx-ink.js";
import type { DocxTrackingRequest } from "./protocol-docx-tracking.js";
import type { DocxPageCommand } from "./protocol-docx-page.js";
import type {
  DocxChartEdit,
  DocxFractionEdit,
  DocxMathEdit,
  DocxScriptEdit,
  DocxRevisionEdit,
  DocxPasteMode,
  Budget,
  DocxRuler,
  DocxRulerEdit,
  DocxSelection,
  DocxPosition,
  NavigationDirection,
  CharacterFormatPatch,
  ParagraphFormatPatch,
  DocxFindOptions,
  CopiedFormat,
  DocxStyleUpdate,
  DocxStyleCreation,
  DocxListEdit,
  DocxListLevelUpdate,
  DocxPageSetup,
  DocxCoverPage,
  DocxPageNumbering,
  DocxColumns,
  DocxPageBorders,
  DocxRunningKind,
  DocxRunningVariant,
  DocxRunningContent,
  DocxBodyField,
  DocxPictureEdit,
  DocxShapeEdit,
  DocxDrawingGestureCommand,
  DocxTableEdit,
  DocxThemeSlot,
  DocxThemeFontEdit,
  DocxBookmarkEdit,
  DocxCommentEdit,
} from "../core/index.js";
import type { DocxNoteRequest } from "./protocol-docx-notes.js";
export type Operation =
  | { operation: "initialize"; module: WebAssembly.Module }
  | DocxTrackingRequest
  | DocxInkRequest
  | DocxNoteRequest
  | { operation: "docxRuler"; revision: number }
  | { operation: "editDocxRuler"; source: DocxRuler; change: DocxRulerEdit }
  | { operation: "editBookmark"; revision: number; change: DocxBookmarkEdit }
  | { operation: "docxComments"; revision: number }
  | { operation: "docxRevisions"; revision: number }
  | {
      operation: "docxRevisionGeometry";
      revision: number;
      layoutId: number;
      revisionId: string;
    }
  | {
      operation: "resolveDocxRevisions";
      revision: number;
      change: DocxRevisionEdit;
    }
  | {
      operation: "navigateComment";
      revision: number;
      direction: "previous" | "next";
    }
  | { operation: "editDocxComment"; revision: number; change: DocxCommentEdit }
  | {
      operation: "setHyperlink";
      revision: number;
      selection: DocxSelection;
      target: string | null;
      text?: string;
    }
  | { operation: "docxThemeFonts"; revision: number }
  | {
      operation: "setDocxThemeFonts";
      revision: number;
      fonts: DocxThemeFontEdit[];
      profile: Record<string, string>;
    }
  | { operation: "docxThemeColors"; revision: number }
  | {
      operation: "setDocxThemeColor";
      revision: number;
      slot: DocxThemeSlot;
      color: string;
    }
  | { operation: "docxOverview"; revision: number }
  | {
      operation: "docxDrawingGesture";
      revision: number;
      change: DocxDrawingGestureCommand;
      profile: Record<string, string>;
    }
  | { operation: "docxPictures"; revision: number }
  | { operation: "docxCharts"; revision: number }
  | {
      operation: "editDocxChart";
      revision: number;
      chart: DocxChartEdit;
      profile: Record<string, string>;
    }
  | { operation: "docxShapes"; revision: number }
  | { operation: "docxMathFractions"; revision: number }
  | { operation: "docxMathScripts"; revision: number }
  | { operation: "docxMathExpressions"; revision: number }
  | {
      operation: "editDocxMath";
      revision: number;
      math: DocxMathEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editDocxMathScript";
      revision: number;
      script: DocxScriptEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editDocxMathFraction";
      revision: number;
      fraction: DocxFractionEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editDocxShape";
      revision: number;
      shape: DocxShapeEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editDocxPicture";
      revision: number;
      picture: DocxPictureEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editDocxTable";
      profile: Record<string, string>;
      revision: number;
      selection: DocxSelection;
      change: DocxTableEdit;
    }
  | {
      operation: "setRunningOptions";
      revision: number;
      section: number;
      first: boolean;
      even: boolean;
      profile: Record<string, string>;
    }
  | { operation: "pageSetup"; revision: number; section: number }
  | { operation: "documentProtection"; revision: number }
  | {
      operation: "setDocumentProtection";
      revision: number;
      enabled: boolean;
      password: string;
    }
  | { operation: "bodyPageField"; revision: number; selection: DocxSelection }
  | {
      operation: "editBodyPageField";
      revision: number;
      selection: DocxSelection;
      field: DocxBodyField;
      profile: Record<string, string>;
    }
  | {
      operation: "insertBodyPageField";
      revision: number;
      field: DocxBodyField;
      profile: Record<string, string>;
    }
  | DocxPageCommand
  | {
      operation: "updateBodyPageFields";
      revision: number;
      profile: Record<string, string>;
    }
  | {
      operation: "setPageColumns";
      revision: number;
      section: number;
      columns: DocxColumns | null;
      profile: Record<string, string>;
    }
  | {
      operation: "runningArea";
      revision: number;
      section: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
    }
  | {
      operation: "setRunningLink";
      revision: number;
      section: number;
      linked: boolean;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
      profile: Record<string, string>;
    }
  | {
      operation: "setRunningArea";
      revision: number;
      section: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
      content: DocxRunningContent[];
      distance: number;
      profile: Record<string, string>;
    }
  | { operation: "setPageBackground"; revision: number; color: string | null }
  | DocxWatermarkRequest
  | {
      operation: "setCoverPage";
      revision: number;
      cover: DocxCoverPage | null;
      profile: Record<string, string>;
    }
  | {
      operation: "setPageBorders";
      revision: number;
      section: number;
      borders: DocxPageBorders | null;
    }
  | { operation: "setPageSetup"; revision: number; page: DocxPageSetup }
  | {
      operation: "setPageNumbering";
      revision: number;
      section: number;
      numbering: DocxPageNumbering | null;
      profile: Record<string, string>;
    }
  | {
      operation: "insertDocxTable";
      revision: number;
      selection: DocxSelection;
      rows: number;
      columns: number;
      profile: Record<string, string>;
    }
  | {
      operation: "updateListLevel";
      revision: number;
      listId: number;
      level: number;
      definition: DocxListLevelUpdate;
    }
  | { operation: "listCatalog"; revision: number }
  | {
      operation: "editList";
      revision: number;
      selection: DocxSelection;
      change: DocxListEdit;
    }
  | {
      operation: "setDefaultTabStop";
      revision: number;
      interval: number | null;
    }
  | { operation: "font"; bytes: Uint8Array; identity: string }
  | { operation: "shape"; text: string; size: number; language: string }
  | { operation: "openDocx"; bytes: Uint8Array; budget: Budget }
  | { operation: "createDocx"; budget: Budget }
  | { operation: "tabDocx"; revision: number; backward: boolean }
  | { operation: "enterDocx"; revision: number }
  | {
      operation: "styleCatalog";
      revision: number;
      kind: "paragraph" | "character";
    }
  | {
      operation: "findDocx";
      revision: number;
      text: string;
      options: DocxFindOptions;
    }
  | {
      operation: "replaceDocxMatches";
      revision: number;
      matches: DocxSelection[];
      text: string;
    }
  | {
      operation: "queryFormatting" | "captureFormat";
      revision: number;
      selection: DocxSelection;
    }
  | {
      operation: "applyFormat";
      revision: number;
      selection: DocxSelection;
      format: CopiedFormat;
      profile: Record<string, string>;
    }
  | {
      operation: "updateStyle";
      revision: number;
      key: string;
      format: DocxStyleUpdate;
    }
  | {
      operation: "createStyle";
      revision: number;
      style: DocxStyleCreation;
    }
  | {
      operation: "deleteStyle";
      revision: number;
      key: string;
      replacement: string;
    }
  | {
      operation: "setCharacterFormat";
      revision: number;
      selection: DocxSelection;
      format: CharacterFormatPatch;
      profile: Record<string, string>;
    }
  | {
      operation: "setParagraphFormat";
      revision: number;
      selection: DocxSelection;
      format: ParagraphFormatPatch;
      profile: Record<string, string>;
    }
  | { operation: "budget" }
  | { operation: "query" | "saveDocx" | "flow" | "editState" }
  | {
      operation: "exportDocxMarkup";
      revision: number;
      format: "html" | "markdown";
      outputBytes: number;
    }
  | {
      operation: "selectDocx";
      revision: number;
      selection: DocxSelection;
    }
  | { operation: "selectAllDocx"; revision: number }
  | {
      operation: "tableClipboard" | "docxClipboard";
      revision: number;
      selection: DocxSelection;
      cut: boolean;
    }
  | {
      operation: "tableFragmentImages" | "bodyFragmentImages";
      revision: number;
      fragment: string;
    }
  | {
      operation: "pasteBodyFragment";
      revision: number;
      selection: DocxSelection;
      fragment: string;
      profile: Record<string, string>;
    }
  | {
      operation: "pasteMarkdown";
      revision: number;
      selection: DocxSelection;
      markdown: string;
      profile: Record<string, string>;
      mode: DocxPasteMode;
    }
  | {
      operation: "pasteHtml";
      revision: number;
      selection: DocxSelection;
      html: string;
      profile: Record<string, string>;
      mode: DocxPasteMode;
    }
  | {
      operation: "markupImages";
      revision: number;
      kind: "html" | "markdown";
      input: string;
      mode: DocxPasteMode;
    }
  | {
      operation: "selectedText";
      revision: number;
      selection: DocxSelection;
      cut: boolean;
    }
  | {
      operation: "replaceRange";
      revision: number;
      selection: DocxSelection;
      text: string;
      inputGroup?: number | undefined;
    }
  | { operation: "undoDocx" | "redoDocx"; revision: number }
  | { operation: "beginComposition"; revision: number }
  | {
      operation: "updateComposition" | "commitComposition";
      revision: number;
      compositionId: number;
      text: string;
    }
  | { operation: "cancelComposition"; revision: number; compositionId: number }
  | {
      operation: "deleteDocx";
      revision: number;
      direction: "backward" | "forward";
    }
  | { operation: "layout"; profile: Record<string, string> }
  | {
      operation: "hitTest";
      layoutId: number;
      page: number;
      x: number;
      y: number;
    }
  | { operation: "caret"; layoutId: number; position: DocxPosition }
  | {
      operation: "navigateDocx";
      revision: number;
      layoutId: number;
      direction: NavigationDirection;
      extend: boolean;
    }
  | {
      operation: "selectionGeometry";
      layoutId: number;
      selection: DocxSelection;
    }
  | {
      operation: "exportPdf";
      outputBytes: number;
      layoutId?: number | undefined;
    }
  | { operation: "imageBytes"; key: string }
  | {
      operation: "image";
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    }
  | { operation: "replaceNode"; node: number; revision: number; text: string };
export type Request = Operation & { id: number };
