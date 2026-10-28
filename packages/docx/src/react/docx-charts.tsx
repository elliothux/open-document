import { useEffect, useState } from "react";
import type { DocumentEditor, DocumentCharts } from "../web/editor.js";
import type { ChartSettings } from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { ChartFields, initialChart } from "@open-document/ui/chart-fields";
import { messages } from "@open-document/ui/messages";
import { DocxDrawingPosition } from "./docx-drawing-position.js";

export function DocxCharts({
  controller,
  state,
  editor,
  disabled,
  insertDisabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  insertDisabled: boolean;
}) {
  const t = messages(state.locale);
  const [catalog, setCatalog] = useState<DocumentCharts>();
  const [id, setId] = useState<number>();
  const [draft, setDraft] = useState<ChartSettings>(initialChart);
  const [width, setWidth] = useState(360),
    [height, setHeight] = useState(240);
  const current = catalog?.items.find((item) => item.id === id);
  const choose = (item: DocumentCharts["items"][number] | undefined) => {
    setId(item?.id);
    if (item?.settings) {
      setDraft(item.settings);
      setWidth(item.width);
      setHeight(item.height);
    }
  };
  const load = async () => {
    const value = await editor.charts();
    setCatalog(value);
    choose(
      value.items.find((item) => item.selected) ??
        value.items.find((item) => item.id === id) ??
        value.items[0],
    );
  };
  const selection = editor.getSnapshot().data.selection;
  useEffect(() => {
    if (
      state.document?.composition ||
      state.document?.dragging ||
      state.document?.paused ||
      state.document?.stopped ||
      !selection ||
      selection.anchor.paragraph !== selection.focus.paragraph ||
      Math.abs(selection.anchor.offset - selection.focus.offset) !== 1
    )
      return;
    let active = true;
    controller.run(async () => {
      try {
        const value = await editor.charts(),
          selected = value.items.find((item) => item.selected);
        if (active && selected) {
          setCatalog(value);
          choose(selected);
        }
      } catch (error) {
        if (active) throw error;
      }
    });
    return () => {
      active = false;
    };
  }, [
    controller,
    editor,
    state.document?.revision,
    state.document?.composition,
    state.document?.dragging,
    state.document?.paused,
    state.document?.stopped,
    selection?.anchor.paragraph,
    selection?.anchor.offset,
    selection?.focus.paragraph,
    selection?.focus.offset,
  ]);
  const stale = catalog?.revision !== editor.getSnapshot().revision;
  const sizeInvalid =
    !Number.isFinite(width) ||
    !Number.isFinite(height) ||
    width < 180 ||
    height < 150 ||
    width > 14400 ||
    height > 14400;
  const invalid = !draft.data || sizeInvalid;
  return (
    <section aria-label={t.chart}>
      <fieldset disabled={disabled}>
        <legend>{t.chart}</legend>
        <button type="button" onClick={() => controller.run(load)}>
          {t.chartLoad}
        </button>
        {!!catalog?.items.length && (
          <label>
            {t.chartChoose}
            <select
              aria-label={t.chartChoose}
              value={id ?? ""}
              onChange={(event) =>
                choose(
                  catalog.items.find(
                    (item) => item.id === Number(event.currentTarget.value),
                  ),
                )
              }
            >
              {catalog.items.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.reason || item.settings?.title || `#${item.id}`}
                </option>
              ))}
            </select>
          </label>
        )}
        <ChartFields draft={draft} setDraft={setDraft} t={t} />
        {(
          [
            [t.objectWidth, width, setWidth, 180],
            [t.objectHeight, height, setHeight, 150],
          ] as const
        ).map(([label, value, update, min]) => (
          <label key={label}>
            {label}
            <input
              aria-label={label}
              type="number"
              min={min}
              max={14400}
              value={Number.isFinite(value) ? value : ""}
              onChange={(event) => update(event.currentTarget.valueAsNumber)}
            />
          </label>
        ))}
        <button
          type="button"
          disabled={insertDisabled || invalid}
          onClick={() =>
            controller.run(async () => {
              await editor.insertChart({ ...draft, width, height });
              await load();
              editor.focus();
            })
          }
        >
          {t.chartInsert}
        </button>
        <button
          type="button"
          disabled={
            stale ||
            !current ||
            !!current.reason ||
            invalid ||
            (!!current.sizeReason &&
              (width !== current.width || height !== current.height))
          }
          onClick={() =>
            controller.run(async () => {
              if (!catalog || id === undefined) return;
              await editor.editChart(catalog, id, { ...draft, width, height });
              await load();
            })
          }
        >
          {t.chartApply}
        </button>
        <button
          type="button"
          disabled={stale || !current || !!current.sizeReason || sizeInvalid}
          onClick={() =>
            controller.run(async () => {
              if (!catalog || id === undefined) return;
              await editor.editChart(catalog, id, {
                action: "resize",
                width,
                height,
              });
              await load();
            })
          }
        >
          {t.chartResize}
        </button>
        <button
          type="button"
          disabled={stale || !current || !!current.deleteReason}
          onClick={() =>
            controller.run(async () => {
              if (!catalog || id === undefined) return;
              await editor.editChart(catalog, id, null);
              await load();
            })
          }
        >
          {t.chartDelete}
        </button>
        {current?.reason && <p>{current.reason}</p>}
        {current?.sizeReason && current.sizeReason !== current.reason && (
          <p>{current.sizeReason}</p>
        )}
        {current?.deleteReason && current.deleteReason !== current.reason && (
          <p>{current.deleteReason}</p>
        )}
        {current && (
          <DocxDrawingPosition
            key={`${current.id}:${catalog?.revision}`}
            controller={controller}
            state={state}
            drawing={current}
            disabled={disabled || stale}
            apply={async (anchor) => {
              if (!catalog) return;
              await editor.editChart(catalog, current.id, {
                action: "position",
                anchor,
              });
              await load();
            }}
          />
        )}
      </fieldset>
    </section>
  );
}
