import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { XlsxSparklineKind } from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxSparkline({
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
  const t = messages(state.locale);
  const query = editor.currentState;
  const cell = query.selection.address;
  const current = query.sparklines.items.find((item) => item.cell === cell);
  const [source, setSource] = useState(current?.source ?? "");
  const [kind, setKind] = useState<XlsxSparklineKind>(current?.kind ?? "line");
  const blocked =
    disabled || !!query.sparklines.readOnlyReason || cell.includes(":");
  const apply = (source: string | null) =>
    controller.run(() =>
      editor.editSheet({ action: "sparkline", cell, source, kind }),
    );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply(source);
      }}
    >
      <fieldset disabled={blocked}>
        <legend>{t.sparklines}</legend>
        <p>{t.sparklineHint}</p>
        <label>
          {t.sparklineSource}
          <input
            aria-label={t.sparklineSource}
            value={source}
            maxLength={256}
            onChange={(event) => setSource(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.sparklineType}
          <select
            aria-label={t.sparklineType}
            value={kind}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "line" || value === "column" || value === "winLoss")
                setKind(value);
            }}
          >
            <option value="line">{t.sparklineLine}</option>
            <option value="column">{t.sparklineColumn}</option>
            <option value="winLoss">{t.sparklineWinLoss}</option>
          </select>
        </label>
        <button type="submit" disabled={!source}>
          {t.sparklineApply}
        </button>
        <button type="button" disabled={!current} onClick={() => apply(null)}>
          {t.sparklineRemove}
        </button>
      </fieldset>
      {query.sparklines.readOnlyReason && (
        <p>{query.sparklines.readOnlyReason}</p>
      )}
    </form>
  );
}
