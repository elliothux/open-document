import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { XlsxSlicer, XlsxSlicers } from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

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
      <button type="button" onClick={() => controller.run(load)}>
        {t.slicerList}
      </button>
      {catalog && !current && <p>{t.pivotReload}</p>}
      {catalog?.reason && <p>{catalog.reason}</p>}
      {catalog && current && !catalog.reason && !catalog.items.length && (
        <p>{t.slicerEmpty}</p>
      )}
      {catalog?.items.map((item) => (
        <SlicerMembers
          key={`${catalog.revision}:${item.name}`}
          item={item}
          state={state}
          disabled={disabled || !current}
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
        />
      ))}
    </fieldset>
  );
}

function SlicerMembers({
  item,
  state,
  disabled,
  apply,
}: {
  item: XlsxSlicer;
  state: UiSnapshot;
  disabled: boolean;
  apply: (indices: number[]) => void;
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
    </fieldset>
  );
}
