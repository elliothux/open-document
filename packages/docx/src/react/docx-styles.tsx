import { useEffect, useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import type { DocxStyleCatalog } from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { DocxStyleEdit } from "./docx-style-edit.js";
import { Icon } from "@open-document/ui/icons";

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
  const currentId = current?.kind === "value" ? current.value : "";
  const [catalog, setCatalog] = useState<DocxStyleCatalog>();
  const [selected, setSelected] = useState(currentId);
  const [newName, setNewName] = useState("");
  useEffect(() => setCatalog(undefined), [editor, kind]);
  useEffect(() => setNewName(""), [editor, kind]);
  useEffect(() => setSelected(currentId), [currentId]);
  const choice = catalog?.styles.find((style) => style.id === selected);
  const fresh = catalog?.revision === state.document?.revision;
  const apply = (style: string | null) => {
    const target = controller.commands.captureTarget();
    if (!target) return;
    const verify = () => controller.commands.assertTarget(target);
    controller.run(async () => {
      if (paragraph)
        await editor.formatting.setParagraphFormat({ style }, verify);
      else await editor.formatting.setCharacterFormat({ style }, verify);
      if (catalog) setCatalog(await editor.formatting.styles(kind));
    });
  };
  const [replacement, setReplacement] = useState("");
  useEffect(
    () => setReplacement(choice?.basedOn ?? ""),
    [choice?.id, choice?.basedOn, editor],
  );
  const replacements = (catalog?.styles ?? []).filter(
    (style) => style.id !== choice?.id && !style.reason,
  );
  const canReplace = replacements.some((style) => style.id === replacement);
  return (
    <fieldset disabled={disabled}>
      <legend>
        <Icon name="format-painter" />
        {paragraph ? t.paragraphStyle : t.characterStyle}
      </legend>
      <button
        type="button"
        onClick={() =>
          controller.run(async () =>
            setCatalog(await editor.formatting.styles(kind)),
          )
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
      {choice?.preview &&
        (fresh ? (
          <div
            className="od-docx-style-preview"
            role="group"
            aria-label={t.stylePreview}
          >
            <span
              style={{
                color: `#${choice.preview.color}`,
                fontFamily: `${JSON.stringify(choice.preview.family)}, serif`,
                fontSize: `${Math.max(9, Math.min(choice.preview.size, 28))}pt`,
                fontWeight: choice.preview.bold ? 700 : 400,
                fontStyle: choice.preview.italic ? "italic" : "normal",
                textDecorationLine:
                  [
                    choice.preview.underline && "underline",
                    choice.preview.strike && "line-through",
                  ]
                    .filter(Boolean)
                    .join(" ") || "none",
              }}
            >
              {choice.name}
            </span>
            <small>
              {choice.preview.family} · {choice.preview.size} pt
            </small>
          </div>
        ) : (
          <p>{t.stylePreviewStale}</p>
        ))}
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
      <button
        type="button"
        disabled={!choice?.canReset}
        onClick={() =>
          controller.run(async () => {
            if (!choice) return;
            await editor.formatting.updateStyle(choice.id, {
              character: {},
              paragraph: {},
              reset: true,
            });
            setCatalog(await editor.formatting.styles(kind));
          })
        }
      >
        {paragraph ? t.resetParagraphStyle : t.resetCharacterStyle}
      </button>
      <DocxStyleEdit
        controller={controller}
        state={state}
        editor={editor}
        kind={kind}
        choice={choice}
        styles={catalog?.styles ?? []}
        refresh={async () => setCatalog(await editor.formatting.styles(kind))}
      />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            const id = await editor.formatting.createStyle({
              name: newName,
              kind,
              ...(choice ? { basedOn: choice.id } : {}),
            });
            setCatalog(await editor.formatting.styles(kind));
            setSelected(id);
            setNewName("");
          });
        }}
      >
        <fieldset disabled={!catalog || !!choice?.reason}>
          <legend>
            <Icon name="format-painter" />
            {t.createBasedStyle}
          </legend>
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
      <label>
        {t.styleReplacement}
        <select
          aria-label={`${paragraph ? t.paragraphStyle : t.characterStyle}: ${t.styleReplacement}`}
          disabled={!choice?.canDelete}
          value={canReplace ? replacement : ""}
          onChange={(event) => setReplacement(event.currentTarget.value)}
        >
          <option value="" disabled>
            {t.chooseStyle}
          </option>
          {replacements.map((style) => (
            <option key={style.id} value={style.id}>
              {style.name}
            </option>
          ))}
        </select>
      </label>
      {choice?.linked && choice.canDelete && <p>{t.deleteLinkedStyle}</p>}
      <button
        type="button"
        disabled={!choice?.canDelete || !canReplace}
        onClick={() =>
          controller.run(async () => {
            if (!choice || !canReplace) return;
            await editor.formatting.deleteStyle(choice.id, replacement);
            setCatalog(await editor.formatting.styles(kind));
            setSelected(replacement);
          })
        }
      >
        {paragraph ? t.deleteParagraphStyle : t.deleteCharacterStyle}
      </button>
    </fieldset>
  );
}
