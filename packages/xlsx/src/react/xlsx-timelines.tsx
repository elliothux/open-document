import { useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import type {
  XlsxTimelines,
  XlsxTimeline,
  XlsxTimelineRange,
} from "../web/xlsx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { CreateTimeline } from "./xlsx-timeline-create.js";
import { AnalysisFrameEditor } from "./xlsx-analysis-frame.js";

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
  const load = async () => setCatalog(await editor.timelines());
  const current =
    catalog?.revision === editor.currentState.revision &&
    catalog.sheet === editor.currentState.sheet;
  return (
    <fieldset disabled={disabled}>
      <legend>{t.timelines}</legend>
      <CreateTimeline
        editor={editor}
        controller={controller}
        state={state}
        disabled={disabled}
        created={load}
      />
      <button type="button" onClick={() => controller.run(load)}>
        {t.timelineList}
      </button>
      {catalog && !current && <p>{t.pivotReload}</p>}
      {catalog?.reason && <p>{catalog.reason}</p>}
      {current && !catalog.reason && !catalog.items.length && (
        <p>{t.timelineEmpty}</p>
      )}
      {current &&
        catalog.items.map((item) => {
          const drawing = editor.currentLayout?.objects.find(
            (object) => object.timeline?.name === item.name,
          );
          return (
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
                <dd>
                  {item.connections.map((pivot) => pivot.name).join(", ")}
                </dd>
              </dl>
              <label>
                {t.timelineLevel}
                <select
                  aria-label={t.timelineLevel}
                  value={item.level}
                  disabled={
                    disabled ||
                    !current ||
                    editor.currentState.protection.protected
                  }
                  onChange={(event) => {
                    const level = Number(event.currentTarget.value);
                    controller.run(async () => {
                      await editor.editSheet({
                        action: "setTimelineLevel",
                        name: item.name,
                        level,
                      });
                      await load();
                    });
                  }}
                >
                  {[
                    t.timelineYears,
                    t.timelineQuarters,
                    t.timelineMonths,
                    t.timelineDays,
                  ].map((label, level) => (
                    <option key={level} value={level}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              <button
                type="button"
                disabled={
                  disabled ||
                  !current ||
                  editor.currentState.protection.protected
                }
                onClick={() =>
                  controller.run(async () => {
                    await editor.editSheet({
                      action: "deleteTimeline",
                      name: item.name,
                    });
                    await load();
                  })
                }
              >
                {t.timelineDelete}
              </button>
              <TimelineRangeForm
                key={`${catalog.revision}:${item.name}`}
                item={item}
                state={state}
                disabled={
                  disabled ||
                  !current ||
                  !item.connections.length ||
                  editor.currentState.protection.protected
                }
                apply={(range) =>
                  controller.run(async () => {
                    await editor.editSheet({
                      action: "filterTimeline",
                      name: item.name,
                      range,
                    });
                    await load();
                  })
                }
              />
              {drawing?.timeline && (
                <AnalysisFrameEditor
                  key={`frame:${catalog.revision}:${item.name}`}
                  kind="timeline"
                  frame={drawing.timeline.frame}
                  state={state}
                  disabled={
                    disabled ||
                    !current ||
                    editor.currentState.protection.protected
                  }
                  apply={(frame) =>
                    controller.run(async () => {
                      await editor.setTimelineFrame(drawing.id, frame);
                      await load();
                    })
                  }
                />
              )}
            </fieldset>
          );
        })}
    </fieldset>
  );
}

function TimelineRangeForm({
  item,
  state,
  disabled,
  apply,
}: {
  item: XlsxTimeline;
  state: UiSnapshot;
  disabled: boolean;
  apply: (range: XlsxTimelineRange | null) => void;
}) {
  const t = messages(state.locale),
    bounds = item.state.bounds;
  const [start, setStart] = useState(
    (item.state.selection ?? bounds).start.slice(0, 10),
  );
  const [end, setEnd] = useState(
    (item.state.selection ?? bounds).end.slice(0, 10),
  );
  return (
    <fieldset disabled={disabled}>
      <legend>{t.timelineRange}</legend>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          apply({
            start:
              start === bounds.start.slice(0, 10)
                ? bounds.start
                : `${start}T00:00:00`,
            end:
              end === bounds.end.slice(0, 10)
                ? bounds.end
                : `${end}T23:59:59.999`,
          });
        }}
      >
        <label>
          {t.timelineStart}
          <input
            aria-label={t.timelineStart}
            type="date"
            required
            min={bounds.start.slice(0, 10)}
            max={bounds.end.slice(0, 10)}
            value={start}
            onChange={(event) => setStart(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.timelineEnd}
          <input
            aria-label={t.timelineEnd}
            type="date"
            required
            min={start || bounds.start.slice(0, 10)}
            max={bounds.end.slice(0, 10)}
            value={end}
            onChange={(event) => setEnd(event.currentTarget.value)}
          />
        </label>
        <button type="submit">{t.timelineApply}</button>
        <button type="button" onClick={() => apply(null)}>
          {t.timelineClear}
        </button>
      </form>
    </fieldset>
  );
}
