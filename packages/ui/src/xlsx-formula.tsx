import { useRef } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { NativeSlot } from "./controls.js";
import { messages } from "./messages.js";

export function XlsxFormula({
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
    field = useRef<HTMLInputElement>(null),
    selection = editor.currentState.selection;
  return (
    <div className="od-formula">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const range = field.current?.value.trim() ?? "";
          controller.run(() => editor.select(range));
        }}
      >
        <input
          key={`${selection.sheet}:${selection.address}`}
          ref={field}
          aria-label={t.cellRange}
          defaultValue={selection.address}
          maxLength={32}
          required
          disabled={disabled}
        />
        <button type="submit" disabled={disabled}>
          {t.goToRange}
        </button>
      </form>
      <label>
        <span>{t.formulaInput}</span>
        <NativeSlot node={editor.formulaBar} />
      </label>
    </div>
  );
}
