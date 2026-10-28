import type { SpreadsheetEditor } from "../web/index.js";
import { mountProduct } from "@open-document/ui";
import type { Product } from "@open-document/ui/types";
import { prepareFile } from "./file.js";
import { FormatCommands, Properties, Sheets } from "./panels.js";
import type { EditorOptions, MountedEditor } from "./types.js";
export type * from "./types.js";
import { XlsxFormula, XlsxStatistics } from "./xlsx-formula.js";
export async function mountEditor(
  container: HTMLElement,
  options: EditorOptions,
): Promise<MountedEditor> {
  const product: Product<SpreadsheetEditor> = {
    format: "xlsx",
    canCreate: true,
    delimited: true,
    accept: ".xlsx,.csv,.tsv",
    readLabel: false,
    extraTabs: false,
    addressStatus: true,
    editReadOnly: true,
    outputs: [
      { kind: "pdf", label: "exportWorkbook" },
      { kind: "pdf-current", label: "exportCurrentSheet" },
      { kind: "csv", label: "exportCsv" },
      { kind: "csv-selection", label: "exportCsvSelection" },
    ],
    prepare: (document, parent, signal) =>
      prepareFile(options, document, parent, signal),
    render(slot, props) {
      if (["edit", "view", "pages", "annotations"].includes(slot))
        return <FormatCommands {...props} tab={slot} />;
      if (slot === "properties")
        return <Properties key={props.state.document?.documentId} {...props} />;
      if (slot === "before-surface")
        return (
          <XlsxFormula
            key={props.state.document?.documentId}
            {...props}
            editor={props.file.editor}
          />
        );
      if (slot === "after-surface") return <Sheets {...props} />;
      if (slot === "status")
        return (
          <XlsxStatistics state={props.state} editor={props.file.editor} />
        );
      return null;
    },
  };
  const mounted = await mountProduct(container, options, product);
  return {
    ...mounted,
    format: "xlsx",
    get editor() {
      return mounted.editor;
    },
  };
}
