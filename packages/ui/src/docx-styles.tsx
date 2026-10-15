import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxStyleCatalog } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxStyleEdit } from "./docx-style-edit.js";

export function DocxStyles({
  controller,
  state,
  editor,
  disabled,
  kind,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  kind: "paragraph" | "character";
}) {
  const t = messages(state.locale);
  const formatting = editor.getSnapshot().data.formatting;
  const current = formatting?.[kind].style;
  const cannotApply = !formatting || !!formatting.reason;
  const paragraph = kind === "paragraph";
  const apply = (style: string | null) =>
    controller.run(() =>
      paragraph
        ? editor.setParagraphFormat({ style })
        : editor.setCharacterFormat({ style }),
    );
  const currentId = current?.kind === "value" ? current.value : "";
  const [catalog, setCatalog] = useState<DocxStyleCatalog>();
  const [selected, setSelected] = useState(currentId);
  const [newName, setNewName] = useState("");
  useEffect(() => setCatalog(undefined), [editor, kind]);
  useEffect(() => setNewName(""), [editor, kind]);
  useEffect(() => setSelected(currentId), [currentId]);
  const choice = catalog?.styles.find((style) => style.id === selected);
  return (
    <fieldset disabled={disabled}>
      <legend>{paragraph ? t.paragraphStyle : t.characterStyle}</legend>
      <button
        type="button"
        onClick={() =>
          controller.run(async () => setCatalog(await editor.styles(kind)))
        }
      >
        {paragraph ? t.loadStyles : t.loadCharacterStyles}
      </button>
      <label>
        {paragraph ? t.paragraphStyle : t.characterStyle}
        <select
          aria-label={paragraph ? t.paragraphStyle : t.characterStyle}
          value={choice ? selected : ""}
          onChange={(event) => setSelected(event.currentTarget.value)}
        >
          <option value="" disabled>
            {current?.kind === "mixed" ? t.mixed : t.chooseStyle}
          </option>
          {catalog?.styles.map((style) => (
            <option key={style.id} value={style.id} disabled={!!style.reason}>
              {style.name}
              {style.reason ? ` (${style.reason})` : ""}
            </option>
          ))}
        </select>
      </label>
      {catalog?.truncated && <p role="status">{t.styleLimit}</p>}
      <button
        type="button"
        disabled={cannotApply || !choice || !!choice.reason}
        onClick={() => apply(selected)}
      >
        {paragraph ? t.applyStyle : t.applyCharacterStyle}
      </button>
      <button type="button" disabled={cannotApply} onClick={() => apply(null)}>
        {paragraph ? t.restoreDefaultStyle : t.clearCharacterStyle}
      </button>
      <DocxStyleEdit
        controller={controller}
        state={state}
        editor={editor}
        kind={kind}
        choice={choice}
        styles={catalog?.styles ?? []}
        refresh={async () => setCatalog(await editor.styles(kind))}
      />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            const id = await editor.createStyle({
              name: newName,
              kind,
              ...(choice ? { basedOn: choice.id } : {}),
            });
            setCatalog(await editor.styles(kind));
            setSelected(id);
            setNewName("");
          });
        }}
      >
        <fieldset disabled={!catalog || !!choice?.reason}>
          <legend>{t.createBasedStyle}</legend>
          <label>
            {t.newStyleName}
            <input
              aria-label={`${paragraph ? t.paragraphStyle : t.characterStyle}: ${t.newStyleName}`}
              required
              maxLength={200}
              value={newName}
              onChange={(event) => setNewName(event.currentTarget.value)}
            />
          </label>
          <button type="submit">
            {paragraph ? t.createParagraphStyle : t.createCharacterStyle}
          </button>
        </fieldset>
      </form>
      {choice?.canDelete && choice.basedOn && (
        <p>
          {t.styleReplacement}:{" "}
          {catalog?.styles.find((style) => style.id === choice.basedOn)?.name ??
            choice.basedOn}
        </p>
      )}
      <button
        type="button"
        disabled={!choice?.canDelete || !choice.basedOn}
        onClick={() =>
          controller.run(async () => {
            if (!choice?.basedOn) return;
            await editor.deleteStyle(choice.id, choice.basedOn);
            setCatalog(await editor.styles(kind));
            setSelected(choice.basedOn);
          })
        }
      >
        {paragraph ? t.deleteParagraphStyle : t.deleteCharacterStyle}
      </button>
    </fieldset>
  );
}
