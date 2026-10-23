import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  checkXlsxTimelineSettings,
  type XlsxPivots,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function CreateTimeline({
  editor,
  controller,
  state,
  disabled,
  created,
}: {
  editor: SpreadsheetEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
  created: () => Promise<void>;
}) {
  const t = messages(state.locale),
    query = editor.currentState;
  const [pivots, setPivots] = useState<XlsxPivots>();
  const [pivot, setPivot] = useState(""),
    [field, setField] = useState(1);
  const [name, setName] = useState("Timeline1"),
    [caption, setCaption] = useState(t.timelines);
  const [width, setWidth] = useState(240),
    [height, setHeight] = useState(120);
  const settings = { pivot, field: field - 1, name, caption, width, height };
  let valid =
    !disabled &&
    pivots?.revision === query.revision &&
    pivots.items.some((item) => item.part === pivot && !item.reason);
  try {
    checkXlsxTimelineSettings(settings);
  } catch {
    valid = false;
  }
  return (
    <fieldset disabled={disabled || query.protection.protected}>
      <legend>{t.timelineCreate}</legend>
      <p>{t.timelineCreateHelp}</p>
      <button
        type="button"
        onClick={() =>
          controller.run(async () => {
            const next = await editor.pivots();
            setPivots(next);
            if (!next.items.some((item) => item.part === pivot && !item.reason))
              setPivot(next.items.find((item) => !item.reason)?.part ?? "");
          })
        }
      >
        {t.timelineLoadPivots}
      </button>
      <label>
        {t.timelinePivot}
        <select
          aria-label={t.timelinePivot}
          value={pivot}
          onChange={(event) => setPivot(event.currentTarget.value)}
        >
          <option value="">{t.choose}</option>
          {pivots?.items
            .filter((item) => !item.reason)
            .map((item) => (
              <option key={item.part} value={item.part}>
                {item.name}
              </option>
            ))}
        </select>
      </label>
      <label>
        {t.timelineField}
        <input
          aria-label={t.timelineField}
          type="number"
          min={1}
          max={64}
          value={field}
          onChange={(event) => setField(event.currentTarget.valueAsNumber)}
        />
      </label>
      <label>
        {t.timelineName}
        <input
          aria-label={t.timelineName}
          maxLength={255}
          value={name}
          onChange={(event) => setName(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.timelineCaption}
        <input
          aria-label={t.timelineCaption}
          maxLength={255}
          value={caption}
          onChange={(event) => setCaption(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.objectWidth}
        <input
          aria-label={t.objectWidth}
          type="number"
          min={0.1}
          max={14400}
          value={width}
          onChange={(event) => setWidth(event.currentTarget.valueAsNumber)}
        />
      </label>
      <label>
        {t.objectHeight}
        <input
          aria-label={t.objectHeight}
          type="number"
          min={0.1}
          max={14400}
          value={height}
          onChange={(event) => setHeight(event.currentTarget.valueAsNumber)}
        />
      </label>
      <button
        type="button"
        disabled={!valid}
        onClick={() =>
          controller.run(async () => {
            await editor.insertTimeline(settings);
            await created();
          })
        }
      >
        {t.timelineInsert}
      </button>
    </fieldset>
  );
}
