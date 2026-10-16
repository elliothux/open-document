import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxTableEdit } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxTables({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [rows, setRows] = useState("2");
  const [columns, setColumns] = useState("2");
  const rowCount = Number(rows),
    columnCount = Number(columns);
  const snapshot = editor.getSnapshot();
  const paragraph = snapshot.data.selection?.focus.paragraph;
  const body = editor.layout.semantics[snapshot.page]?.lines.some(
    (line) => line.paragraph === paragraph && line.container === 0,
  );
  const cell = editor.layout.semantics[snapshot.page]?.lines.some(
    (line) => line.paragraph === paragraph && line.container > 0,
  );
  return (
    <section aria-label={t.insertTable}>
      <h3>{t.insertTable}</h3>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.insertTable(rowCount, columnCount));
        }}
      >
        <fieldset disabled={disabled || !body}>
          <label>
            {t.tableRows}
            <input
              type="number"
              min={1}
              max={1000}
              required
              value={rows}
              onChange={(event) => setRows(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.tableColumns}
            <input
              type="number"
              min={1}
              max={63}
              required
              value={columns}
              onChange={(event) => setColumns(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={
              !Number.isInteger(rowCount) ||
              !Number.isInteger(columnCount) ||
              rowCount * columnCount > 4096
            }
          >
            {t.insertTable}
          </button>
        </fieldset>
      </form>
      <fieldset disabled={disabled || !cell}>
        <legend>
          {t.tableRows} / {t.tableColumns}
        </legend>
        {(
          [
            "rowBefore",
            "rowAfter",
            "deleteRow",
            "columnBefore",
            "columnAfter",
            "deleteColumn",
          ] satisfies DocxTableEdit[]
        ).map((change) => (
          <button
            key={change}
            type="button"
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => controller.run(() => editor.editTable(change))}
          >
            {t[change]}
          </button>
        ))}
      </fieldset>
    </section>
  );
}
