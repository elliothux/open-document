import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { XlsxTimelines } from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxTimelinesPanel({
  editor,
  controller,
  state,
  disabled,
}: {
  editor: SpreadsheetEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [catalog, setCatalog] = useState<XlsxTimelines>();
  const current =
    catalog?.revision === editor.currentState.revision &&
    catalog.sheet === editor.currentState.sheet;
  return (
    <fieldset disabled={disabled}>
      <legend>{t.timelines}</legend>
      <button
        type="button"
        onClick={() =>
          controller.run(async () => setCatalog(await editor.timelines()))
        }
      >
        {t.timelineList}
      </button>
      {catalog && !current && <p>{t.pivotReload}</p>}
      {catalog?.reason && <p>{catalog.reason}</p>}
      {current && !catalog.reason && !catalog.items.length && (
        <p>{t.timelineEmpty}</p>
      )}
      {current &&
        catalog.items.map((item) => (
          <fieldset key={item.name}>
            <legend>{item.caption}</legend>
            <p>{t.timelineReadOnly}</p>
            <dl>
              <dt>{t.timelineSource}</dt>
              <dd>{item.sourceName}</dd>
              <dt>{t.timelineBounds}</dt>
              <dd>
                {item.state.bounds.start} – {item.state.bounds.end}
              </dd>
              <dt>{t.timelineSelection}</dt>
              <dd>
                {item.state.selection
                  ? `${item.state.selection.start} – ${item.state.selection.end}`
                  : t.timelineUnselected}
              </dd>
              <dt>{t.timelineConnections}</dt>
              <dd>{item.connections.map((pivot) => pivot.name).join(", ")}</dd>
            </dl>
          </fieldset>
        ))}
    </fieldset>
  );
}
