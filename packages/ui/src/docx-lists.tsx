import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import {
  listFormats,
  type DocxListCatalog,
  type DocxListEdit,
  type ListFormat,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxListLevelEdit } from "./docx-list-level.js";

export function DocxLists({
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
  const data = editor.getSnapshot().data;
  const value = data.formatting?.list;
  const current = value?.kind === "value" ? value.value : undefined;
  const [catalog, setCatalog] = useState<DocxListCatalog>();
  const [selected, setSelected] = useState("");
  const [level, setLevel] = useState(0);
  const [format, setFormat] = useState<ListFormat>("decimal");
  const [start, setStart] = useState("1");
  useEffect(() => setCatalog(undefined), [editor]);
  useEffect(() => {
    setSelected(current ? String(current.id) : "");
    setLevel(current?.level ?? 0);
  }, [current?.id, current?.level, editor]);
  const choice = catalog?.lists.find((list) => String(list.id) === selected);
  const currentLevel = catalog?.lists
    .find((list) => list.id === current?.id)
    ?.levels.find((item) => item.level === current?.level);
  const cannotEdit = !data.formatting || !!data.formatting.reason;
  const collapsed =
    data.selection?.anchor.paragraph === data.selection?.focus.paragraph &&
    data.selection?.anchor.offset === data.selection?.focus.offset;
  const change = (change: DocxListEdit) =>
    controller.run(async () => {
      await editor.editList(change);
      setCatalog(await editor.lists());
    });
  return (
    <fieldset disabled={disabled}>
      <legend>{t.lists}</legend>
      <button
        type="button"
        onClick={() =>
          controller.run(async () => setCatalog(await editor.lists()))
        }
      >
        {t.loadLists}
      </button>
      <label>
        {t.existingList}
        <select
          aria-label={t.existingList}
          value={choice ? selected : ""}
          onChange={(event) => {
            const selected = event.currentTarget.value;
            setSelected(selected);
            const next = catalog?.lists.find(
              (list) => String(list.id) === selected,
            );
            if (!next?.levels.some((item) => item.level === level))
              setLevel(next?.levels[0]?.level ?? 0);
          }}
        >
          <option value="" disabled>
            {value?.kind === "mixed" ? t.mixed : t.chooseList}
          </option>
          {catalog?.lists.map((list, index) => (
            <option key={list.id} value={list.id} disabled={!!list.reason}>
              {t.list} {index + 1}
              {list.preview ? `: ${list.preview}` : ""}
              {list.reason ? ` (${list.reason})` : ""}
            </option>
          ))}
        </select>
      </label>
      {catalog?.truncated && <p role="status">{t.listLimit}</p>}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          change({ action: "create", format });
        }}
      >
        <label>
          {t.listFormat}
          <select
            aria-label={t.listFormat}
            value={format}
            onChange={(event) => {
              const next = listFormats.find(
                (format) => format === event.currentTarget.value,
              );
              if (next) setFormat(next);
            }}
          >
            {listFormats.map((format) => (
              <option key={format} value={format}>
                {t[`listFormat_${format}`]}
              </option>
            ))}
          </select>
        </label>
        <button type="submit" disabled={cannotEdit}>
          {t.createList}
        </button>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (choice) change({ action: "apply", id: choice.id, level });
        }}
      >
        <label>
          {t.listLevel}
          <select
            aria-label={t.listLevel}
            disabled={!choice}
            value={level}
            onChange={(event) => setLevel(Number(event.currentTarget.value))}
          >
            {(choice?.levels ?? []).map((item) => (
              <option key={item.level} value={item.level}>
                {item.level + 1}
              </option>
            ))}
          </select>
        </label>
        <button
          type="submit"
          disabled={
            cannotEdit ||
            !choice ||
            !!choice.reason ||
            !choice.levels.some((item) => item.level === level)
          }
        >
          {t.applyList}
        </button>
      </form>
      {([-1, 1] as const).map((delta) => (
        <button
          key={delta}
          type="button"
          disabled={
            cannotEdit ||
            (value?.kind !== "mixed" &&
              (!current ||
                !catalog?.lists
                  .find((list) => list.id === current.id)
                  ?.levels.some(
                    (item) => item.level === current.level + delta,
                  )))
          }
          onClick={() => change({ action: "level", increase: delta > 0 })}
        >
          {delta < 0 ? t.decreaseListLevel : t.increaseListLevel}
        </button>
      ))}
      <button
        type="button"
        disabled={cannotEdit || (value?.kind !== "mixed" && !current)}
        onClick={() => change({ action: "remove" })}
      >
        {t.removeList}
      </button>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          change({ action: "restart", start: Number(start) });
        }}
      >
        <label>
          {t.listStart}
          <input
            aria-label={t.listStart}
            type="number"
            required
            min={0}
            max={2147483646}
            step={1}
            value={start}
            onChange={(event) => setStart(event.currentTarget.value)}
          />
        </label>
        <button
          type="submit"
          disabled={
            cannotEdit ||
            !current ||
            !collapsed ||
            !currentLevel ||
            currentLevel.format === "bullet"
          }
        >
          {t.restartList}
        </button>
      </form>
      {choice &&
        !choice.reason &&
        choice.levels
          .filter((item) => item.level === level)
          .map((item) => (
            <DocxListLevelEdit
              key={`${editor.getSnapshot().documentId}:${choice.id}:${level}:${catalog?.revision}`}
              controller={controller}
              state={state}
              editor={editor}
              id={choice.id}
              level={item}
              availableLevels={choice.levels.map((level) => level.level)}
              stale={catalog?.revision !== data.revision}
              refresh={async () => setCatalog(await editor.lists())}
            />
          ))}
    </fieldset>
  );
}
