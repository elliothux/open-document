export { pasteDocxCells, pasteDocxSelection } from "./clipboard-input.js";

export { checkDocxComment } from "../core/foundation.js";
export type * from "./foundation-types.js";
export {
  checkDocxHyperlink,
  checkDocxBookmark,
  highlightColors,
  DOCX_SOFT_BREAK,
  DOCX_PAGE_BREAK,
  DOCX_COLUMN_BREAK,
  listFormats,
  noteNumberFormats,
  sourceKinds,
} from "../core/foundation.js";

import type { EngineHandle } from "@open-document/wasm";
import type { DocxCommand, DocxResult } from "../core/docx-command.js";
export type { DocxCommand, DocxResult } from "../core/docx-command.js";
import {
  prepareDocxFragmentImages,
  prepareDocxImages,
} from "./document-fragment-images.js";
export type { DocxInputLimits } from "../core/docx-input.js";
import { DocxWorkerSession } from "../headless.js";

import { checkViewCommand } from "@open-document/web-core/view-mode";

const viewCommands = new Set<DocxCommand["operation"]>([
  "layout",
  "editState",
  "docxSelectionView",
  "hitTest",
  "selectDocx",
  "selectAllDocx",
  "navigateDocx",
  "clipboard",
  "tableClipboard",
  "findDocx",
  "overview",
  "revisions",
  "revisionGeometry",
  "comments",
  "navigateComment",
  "styles",
  "lists",
  "charts",
  "pictures",
  "shapes",
  "mathExpressions",
  "mathFractions",
  "mathScripts",
  "indexes",
  "pageSetup",
  "ruler",
  "runningArea",
  "notes",
  "noteNumbering",
  "bodyPageField",
  "sources",
  "tableOfContents",
  "tracking",
  "themeColors",
  "themeFonts",
  "watermark",
  "documentProtection",
  "exportPdf",
  "exportMarkup",
  "saveDocx",
  "imagePixels",
  "imageSource",
  "cancelComposition",
  "addImage",
]);

export class FoundationClient extends DocxWorkerSession {
  readOnly = false;

  protected override checkCommand(command: DocxCommand): void {
    checkViewCommand(this.readOnly, viewCommands, command.operation);
    super.checkCommand(command);
  }

  static override async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<FoundationClient> {
    return new FoundationClient(await this.connect(engine, workerUrl, signal));
  }
  override async execute<C extends DocxCommand>(
    command: C,
  ): Promise<DocxResult<C>> {
    this.checkCommand(command);
    if (
      command.operation === "pasteHtml" ||
      command.operation === "pasteMarkdown"
    ) {
      await prepareDocxImages(
        this,
        await this.execute({
          operation: "markupImages",
          revision: command.revision,
          kind: command.operation === "pasteHtml" ? "html" : "markdown",
          input:
            command.operation === "pasteHtml" ? command.html : command.markdown,
          mode: command.mode,
          preparePixels: true,
        }),
      );
    } else if (command.operation === "pasteBodyFragment") {
      await prepareDocxFragmentImages(
        this,
        command.revision,
        command.fragment,
        "body",
      );
    } else if (
      command.operation === "editTable" &&
      command.change.action === "pasteFragment"
    ) {
      await prepareDocxFragmentImages(
        this,
        command.revision,
        command.change.fragment,
      );
    }
    return super.execute(command);
  }
}
