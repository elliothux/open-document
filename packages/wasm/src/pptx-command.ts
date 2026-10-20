import type { PptxCommand } from "./pptx.js";

const names: ReadonlySet<string> = new Set([
  "openPptx",
  "createPptx",
  "queryPptx",
  "dateTimePptx",
  "followPptxHyperlink",
  "findPptx",
  "replacePptxMatches",
  "editPptxObjects",
  "editPptxSlides",
  "selectPptx",
  "replacePptx",
  "deletePptx",
  "undoPptx",
  "redoPptx",
  "savePptx",
  "copyPptx",
  "layoutPptx",
  "printLayoutPptx",
  "hitPptx",
  "selectionPptx",
  "navigatePptx",
  "beginPptx",
  "beginGuidePptx",
  "transformPptx",
  "dragPptx",
  "finishPptx",
  "cancelPptx",
  "imageBytesPptx",
  "mediaBytesPptx",
  "imagePptx",
  "imageKeysPptx",
  "exportPptxPdf",
  "controlShowPptx",
  "inkShowPptx",
  "mediaShowPptx",
  "layoutShowPptx",
  "imageKeysShowPptx",
]);
export function isPptxCommand(value: {
  operation: string;
}): value is PptxCommand {
  return names.has(value.operation);
}
