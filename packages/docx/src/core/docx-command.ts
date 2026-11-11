import { docxFormatCommands } from "./docx-command-format.js";
import { docxEditingCommands } from "./docx-command-editing.js";
import { docxPreviewCommands } from "./docx-command-preview.js";
import { docxSelectionCommands } from "./docx-command-selection.js";
import { docxInkCommands } from "./docx-command-ink.js";
import { docxMathCommands } from "./docx-command-math.js";
import { docxClipboardCommands } from "./docx-command-clipboard.js";
import { docxFieldsCommands } from "./docx-command-fields.js";
import { docxPageCommands } from "./docx-command-page.js";
import { docxReviewCommands } from "./docx-command-review.js";
import type { PageLayout, LayoutPreparation } from "./preview.js";

export const docxCommands = {
  ...docxFormatCommands,
  ...docxEditingCommands,
  ...docxPreviewCommands,
  ...docxSelectionCommands,
  ...docxInkCommands,
  ...docxMathCommands,
  ...docxClipboardCommands,
  ...docxFieldsCommands,
  ...docxPageCommands,
  ...docxReviewCommands,
};

export type DocxCommand = {
  [Operation in keyof typeof docxCommands]: {
    operation: Operation;
  } & Parameters<(typeof docxCommands)[Operation]>[1];
}[keyof typeof docxCommands];

export type DocxResult<C extends DocxCommand> = C extends {
  operation: "layout";
}
  ? "prepareImages" extends keyof C
    ? C extends { prepareImages?: false | undefined }
      ? PageLayout
      : LayoutPreparation
    : PageLayout
  : ReturnType<(typeof docxCommands)[C["operation"]]>;
