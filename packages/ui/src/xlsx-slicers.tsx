import { useState, type ReactNode } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  checkXlsxSlicerSettings,
  type XlsxSlicer,
  type XlsxSlicers,
  type XlsxPivots,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { AnalysisFrameEditor } from "./xlsx-analysis-frame.js";

export function XlsxSlicersPanel({
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
  const t = messages(state.locale),
    query = editor.currentState;
  const [catalog, setCatalog] = useState<XlsxSlicers>();
  const current =
    catalog?.revision === query.revision && catalog.sheet === query.sheet;
  const load = async () => setCatalog(await editor.slicers());
  return (
    <fieldset disabled={disabled}>
      <legend>{t.slicers}</legend>
      <CreateSlicer
        editor={editor}
        controller={controller}
        state={state}
        disabled={disabled}
        created={load}
      />
      <button type="button" onClick={() => controller.run(load)}>
        {t.slicerList}
      </button>
      {catalog && !current && <p>{t.pivotReload}</p>}
      {catalog?.reason && <p>{catalog.reason}</p>}
      {catalog && current && !catalog.reason && !catalog.items.length && (
        <p>{t.slicerEmpty}</p>
      )}
      {catalog?.items.map((item) => {
        const drawing = editor.currentLayout?.objects.find(
          (object) => object.slicer?.name === item.name,
        );
        return (
          <SlicerMembers
            key={`${catalog.revision}:${item.name}`}
            item={item}
            state={state}
            disabled={disabled || !current}
            remove={() =>
              controller.run(async () => {
                await editor.editSheet({
                  action: "deleteSlicer",
                  name: item.name,
                });
                await load();
              })
            }
            apply={(indices) =>
              controller.run(async () => {
                await editor.editSheet({
                  action: "filterSlicer",
                  name: item.name,
                  indices,
                });
                await load();
              })
            }
          >
            {drawing?.slicer && (
              <AnalysisFrameEditor
                kind="slicer"
                frame={drawing.slicer.frame}
                state={state}
                disabled={item.lockedPosition}
                apply={(frame) =>
                  controller.run(async () => {
                    await editor.setSlicerFrame(drawing.id, frame);
                    await load();
                  })
                }
              />
            )}
          </SlicerMembers>
        );
      })}
    </fieldset>
  );
}

function CreateSlicer({
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
  const [pivot, setPivot] = useState("");
  const [field, setField] = useState(1),
    [name, setName] = useState("Slicer1"),
    [caption, setCaption] = useState(t.slicers);
  const [width, setWidth] = useState(144),
    [height, setHeight] = useState(132);
  const settings = { pivot, field: field - 1, name, caption, width, height };
  let valid =
    !disabled &&
    pivots?.revision === query.revision &&
    pivots.items.some((item) => item.part === pivot);
  try {
    checkXlsxSlicerSettings(settings);
  } catch {
    valid = false;
  }
  return (
    <fieldset disabled={disabled}>
      <legend>{t.slicerCreate}</legend>
      <p>{t.slicerCreateHelp}</p>
      <button
        type="button"
        onClick={() =>
          controller.run(async () => {
            const next = await editor.pivots();
            setPivots(next);
            if (!next.items.some((item) => item.part === pivot))
              setPivot(next.items[0]?.part ?? "");
          })
        }
      >
        {t.slicerLoadPivots}
      </button>
      <label>
        {t.slicerPivot}
        <select
          aria-label={t.slicerPivot}
          value={pivot}
          onChange={(event) => setPivot(event.currentTarget.value)}
        >
          <option value="">{t.choose}</option>
          {pivots?.items.map((item) => (
            <option key={item.part} value={item.part}>
              {item.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        {t.slicerField}
        <input
          aria-label={t.slicerField}
          type="number"
          min={1}
          max={64}
          value={field}
          onChange={(event) => setField(event.currentTarget.valueAsNumber)}
        />
      </label>
      <label>
        {t.slicerName}
        <input
          aria-label={t.slicerName}
          maxLength={255}
          value={name}
          onChange={(event) => setName(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.slicerCaption}
        <input
          aria-label={t.slicerCaption}
          maxLength={255}
          value={caption}
          onChange={(event) => setCaption(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.slicerWidth}
        <input
          aria-label={t.slicerWidth}
          type="number"
          min={0.1}
          max={14400}
          value={width}
          onChange={(event) => setWidth(event.currentTarget.valueAsNumber)}
        />
      </label>
      <label>
        {t.slicerHeight}
        <input
          aria-label={t.slicerHeight}
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
            await editor.insertSlicer(settings);
            await created();
          })
        }
      >
        {t.slicerInsert}
      </button>
    </fieldset>
  );
}

function SlicerMembers({
  item,
  state,
  disabled,
  apply,
  remove,
  children,
}: {
  item: XlsxSlicer;
  state: UiSnapshot;
  disabled: boolean;
  apply: (indices: number[]) => void;
  remove: () => void;
  children?: ReactNode;
}) {
  const t = messages(state.locale);
  const [indices, setIndices] = useState(
    item.members
      .filter((member) => member.selected)
      .map((member) => member.index),
  );
  return (
    <fieldset disabled={disabled}>
      <legend>{item.caption || item.name}</legend>
      <label>
        {t.slicerMembers}
        <select
          multiple
          aria-label={t.slicerMembers}
          value={indices.map(String)}
          onChange={(event) =>
            setIndices(
              Array.from(event.currentTarget.selectedOptions, (option) =>
                Number(option.value),
              ),
            )
          }
        >
          {item.members.map((member) => (
            <option key={member.index} value={member.index}>
              {member.value.kind === "blank" ? t.pivotBlank : member.label}
              {member.hasData ? "" : ` (${t.slicerNoData})`}
            </option>
          ))}
        </select>
      </label>
      <button
        type="button"
        onClick={() => setIndices(item.members.map((member) => member.index))}
      >
        {t.slicerAll}
      </button>
      <button
        type="button"
        disabled={!indices.length}
        onClick={() => apply(indices)}
      >
        {t.slicerApply}
      </button>
      {!indices.length && <p>{t.pivotFilterEmpty}</p>}
      <button type="button" onClick={remove}>
        {t.slicerDelete}
      </button>
      {children}
    </fieldset>
  );
}
