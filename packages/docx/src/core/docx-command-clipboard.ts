import type { DocxSelection } from "./docx-hit.js";
import { type EditState } from "./docx-format.js";

import {
  checkDocxTableEdit,
  type DocxFragmentImages,
  type DocxTableClipboard,
} from "./docx-table.js";
import {
  type DocxClipboard,
  type DocxPasteMode,
  checkDocxPasteMode,
  checkMarkdown,
  checkHtml,
} from "./docx-clipboard.js";
import type { DocxRuntime } from "./docx-session.js";

function fragmentImages(
  session: DocxRuntime,
  request: object,
): DocxFragmentImages {
  const result = session.call<DocxFragmentImages<number>>(request);
  return {
    ...result,
    images: result.images.map((image) => ({
      ...image,
      bytes: session.outputBytes(image.bytes),
    })),
  };
}

export const docxClipboardCommands = {
  markupImages(
    session: DocxRuntime,
    {
      revision,
      kind,
      input,
      mode = "source",
      preparePixels,
    }: {
      revision: number;
      kind: "html" | "markdown";
      input: string;
      mode?: DocxPasteMode | undefined;
      preparePixels?: true;
    },
  ) {
    checkDocxPasteMode(mode);
    if (kind === "html")
      checkHtml(input, session.inputLimits().markupSourceUnits);
    else if (kind === "markdown")
      checkMarkdown(input, session.inputLimits().markupSourceUnits);
    else throw new Error("Unknown markup input format");
    return fragmentImages(session, {
      operation: "markupImages",
      revision,
      kind,
      input,
      mode,
      ...(preparePixels ? { preparePixels } : {}),
    });
  },
  pasteHtml(
    session: DocxRuntime,
    {
      revision,
      selection,
      html,
      profile,
      mode = "source",
    }: {
      revision: number;
      selection: DocxSelection;
      html: string;
      profile: Record<string, string>;
      mode?: DocxPasteMode | undefined;
    },
  ) {
    checkHtml(html, session.inputLimits().markupSourceUnits);
    checkDocxPasteMode(mode);
    return session.call<EditState>({
      operation: "pasteHtml",
      revision,
      selection,
      html,
      profile,
      mode,
    });
  },
  pasteMarkdown(
    session: DocxRuntime,
    {
      revision,
      selection,
      markdown,
      profile,
      mode = "source",
    }: {
      revision: number;
      selection: DocxSelection;
      markdown: string;
      profile: Record<string, string>;
      mode?: DocxPasteMode | undefined;
    },
  ) {
    checkMarkdown(markdown, session.inputLimits().markupSourceUnits);
    checkDocxPasteMode(mode);
    return session.call<EditState>({
      operation: "pasteMarkdown",
      revision,
      selection,
      markdown,
      profile,
      mode,
    });
  },
  clipboard(
    session: DocxRuntime,
    {
      revision,
      selection,
      cut = false,
    }: {
      revision: number;
      selection: DocxSelection;
      cut?: boolean | undefined;
    },
  ): DocxClipboard {
    return session.call<DocxClipboard>({
      operation: "docxClipboard",
      revision,
      selection,
      cut,
    });
  },
  bodyFragmentImages(
    session: DocxRuntime,
    {
      revision,
      fragment,
      preparePixels,
    }: {
      revision: number;
      fragment: string;
      preparePixels?: true;
    },
  ) {
    checkDocxTableEdit(
      { action: "pasteFragment", fragment },
      session.inputLimits,
    );
    return fragmentImages(session, {
      operation: "bodyFragmentImages",
      revision,
      fragment,
      ...(preparePixels ? { preparePixels } : {}),
    });
  },
  pasteBodyFragment(
    session: DocxRuntime,
    {
      revision,
      selection,
      fragment,
      profile,
    }: {
      revision: number;
      selection: DocxSelection;
      fragment: string;
      profile: Record<string, string>;
    },
  ) {
    checkDocxTableEdit(
      { action: "pasteFragment", fragment },
      session.inputLimits,
    );
    return session.call<EditState>({
      operation: "pasteBodyFragment",
      revision,
      selection,
      fragment,
      profile,
    });
  },
  tableClipboard(
    session: DocxRuntime,
    {
      revision,
      selection,
      cut = false,
    }: {
      revision: number;
      selection: DocxSelection;
      cut?: boolean | undefined;
    },
  ): DocxTableClipboard {
    return session.call<DocxTableClipboard>({
      operation: "tableClipboard",
      revision,
      selection,
      cut,
    });
  },
  tableFragmentImages(
    session: DocxRuntime,
    {
      revision,
      fragment,
      preparePixels,
    }: {
      revision: number;
      fragment: string;
      preparePixels?: true;
    },
  ) {
    checkDocxTableEdit(
      { action: "pasteFragment", fragment },
      session.inputLimits,
    );
    return fragmentImages(session, {
      operation: "tableFragmentImages",
      revision,
      fragment,
      ...(preparePixels ? { preparePixels } : {}),
    });
  },
  selectedText(
    session: DocxRuntime,
    {
      revision,
      selection,
      cut = false,
    }: {
      revision: number;
      selection: DocxSelection;
      cut?: boolean | undefined;
    },
  ): string {
    return session.call<string>({
      operation: "selectedText",
      revision,
      selection,
      cut,
    });
  },
};
