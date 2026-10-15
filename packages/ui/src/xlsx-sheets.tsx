import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxSheets({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.currentState;
  const [chosen, setChosen] = useState("");
  const [name, setName] = useState("");
  const position = query.sheets.findIndex((sheet) => sheet.id === query.sheet);
  const visible = query.sheets.filter((sheet) => sheet.state === "visible");
  const hidden = query.sheets.filter((sheet) => sheet.state === "hidden");
  const target =
    hidden.find((sheet) => sheet.id === chosen)?.id ?? hidden[0]?.id ?? "";
  return (
    <nav
      className="od-sheets"
      aria-label={t.sheet}
      onMouseDown={(event) => {
        // The queued sheet command commits the draft without losing the click to blur.
        if (
          event.button === 0 &&
          event.target instanceof Element &&
          event.target.closest("button")
        )
          event.preventDefault();
      }}
    >
      {visible.map((sheet) => (
        <button
          type="button"
          key={sheet.id}
          aria-current={sheet.id === query.sheet ? "page" : undefined}
          disabled={disabled}
          onClick={() => controller.run(() => editor.select("A1", sheet.id))}
        >
          {sheet.name}
        </button>
      ))}
      <fieldset disabled={disabled || !!query.sheetEditReason}>
        <legend>{t.manageSheets}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.editSheet({ action: "rename", name });
              setName("");
            });
          }}
        >
          <label>
            {t.sheetName}
            <input
              value={name}
              maxLength={31}
              required
              disabled={!!query.sheetRenameReason}
              onChange={(event) => setName(event.currentTarget.value)}
            />
          </label>
          <button type="submit" disabled={!!query.sheetRenameReason || !name}>
            {t.renameSheet}
          </button>
        </form>
        {query.sheetRenameReason &&
          query.sheetRenameReason !== query.sheetEditReason && (
            <p>{query.sheetRenameReason}</p>
          )}
        <button
          type="button"
          disabled={position <= 0}
          onClick={() =>
            controller.run(() =>
              editor.editSheet({ action: "move", index: position - 1 }),
            )
          }
        >
          {t.sheetEarlier}
        </button>
        <button
          type="button"
          disabled={position >= query.sheets.length - 1}
          onClick={() =>
            controller.run(() =>
              editor.editSheet({ action: "move", index: position + 1 }),
            )
          }
        >
          {t.sheetLater}
        </button>
        <button
          type="button"
          disabled={visible.length <= 1}
          onClick={() =>
            controller.run(() =>
              editor.editSheet({ action: "visibility", state: "hidden" }),
            )
          }
        >
          {t.hideSheet}
        </button>
        <label>
          {t.hiddenSheet}
          <select
            value={target}
            disabled={!hidden.length}
            onChange={(event) => setChosen(event.currentTarget.value)}
          >
            {!hidden.length && <option value="">{t.choose}</option>}
            {hidden.map((sheet) => (
              <option key={sheet.id} value={sheet.id}>
                {sheet.name}
              </option>
            ))}
          </select>
        </label>
        <button
          type="button"
          disabled={!target}
          onClick={() =>
            controller.run(() =>
              editor.editSheet(
                { action: "visibility", state: "visible" },
                target,
              ),
            )
          }
        >
          {t.showSheet}
        </button>
      </fieldset>
      {query.sheetEditReason && <p>{query.sheetEditReason}</p>}
    </nav>
  );
}
