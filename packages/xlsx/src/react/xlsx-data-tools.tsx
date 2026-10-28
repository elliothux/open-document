import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { XlsxTextColumns } from "./xlsx-text-columns.js";
import { XlsxDuplicates } from "./xlsx-duplicates.js";
import { XlsxConsolidate } from "./xlsx-consolidate.js";
import { XlsxSubtotal } from "./xlsx-subtotal.js";

export function XlsxDataTools(props: {
  editor: SpreadsheetEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
}) {
  const key = `${props.state.document?.documentId}:${props.editor.currentState.sheet}:${props.editor.currentState.selection.address}`;
  return (
    <>
      <XlsxTextColumns key={`columns:${key}`} {...props} />
      <XlsxDuplicates key={`duplicates:${key}`} {...props} />
      <XlsxSubtotal key={`subtotal:${key}`} {...props} />
      <XlsxConsolidate
        key={`consolidate:${props.state.document?.documentId}:${props.editor.currentState.sheet}`}
        {...props}
      />
    </>
  );
}
