import type { SpreadsheetEditor } from "../web/index.js";
import { mountProduct, ProductEditor } from "@open-document/ui";
import type { EditorEvents, Product } from "@open-document/ui/types";
import { prepareFile } from "./file.js";
import {
  FormatCommands,
  Properties,
  Sheets,
  xlsxContextActions,
  xlsxTabs,
} from "./panels.js";
import { messages } from "@open-document/ui/messages";
import type { EditorOptions, MountedEditor } from "./types.js";
export type * from "./types.js";
import { XlsxFormula, XlsxStatistics } from "./xlsx-formula.js";
function product(
  options: EditorOptions,
): Product<SpreadsheetEditor> & { format: "xlsx" } {
  return {
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
    prepare: (document, parent, signal, locale) =>
      prepareFile({ ...options, locale }, document, parent, signal),
    selectionKey: (editor) => JSON.stringify(editor.currentState.selection),
    tabs: () => xlsxTabs,
    contextActions: xlsxContextActions,
    commands({ file, state, disabled }) {
      const t = messages(state.locale);
      const current = file.editor.currentState.formatting;
      const reason =
        state.mode === "view"
          ? t.viewOnly
          : current.readOnlyReason || (disabled ? t.commandUnavailable : "");
      return (["bold", "italic", "underline", "strike"] as const).map((id) => ({
        id,
        label: t[id],
        icon: id === "strike" ? "strikethrough" : id,
        pressed: current[id] ?? "mixed",
        ...(reason ? { disabledReason: reason } : {}),
        run: (verify) =>
          file.editor.formatCells(
            { [id]: file.editor.currentState.formatting[id] !== true },
            verify,
          ),
      }));
    },
    render(slot, props) {
      if (xlsxTabs.some((tab) => tab.id === slot))
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
}

export type XlsxEditorProps = EditorOptions & EditorEvents<MountedEditor>;

export function XlsxEditor({
  onReady,
  onChange,
  onError,
  ...options
}: XlsxEditorProps) {
  return (
    <ProductEditor
      product={product}
      options={options}
      onReady={onReady}
      onChange={onChange}
      onError={onError}
    />
  );
}

export function mountEditor(
  container: HTMLElement,
  options: EditorOptions,
): Promise<MountedEditor> {
  return mountProduct(container, options, product);
}
