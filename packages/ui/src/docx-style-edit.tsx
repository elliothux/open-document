import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxStyleCatalog,
  ParagraphFormatPatch,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxStyleEdit({
  controller,
  state,
  editor,
  kind,
  choice,
  styles,
  refresh,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  kind: "paragraph" | "character";
  choice: DocxStyleCatalog["styles"][number] | undefined;
  styles: DocxStyleCatalog["styles"];
  refresh: () => Promise<void>;
}) {
  const t = messages(state.locale);
  const label = kind === "paragraph" ? t.paragraphStyle : t.characterStyle;
  const [name, setName] = useState(choice?.name ?? "");
  const [size, setSize] = useState("");
  const [align, setAlign] = useState("");
  const [basedOn, setBasedOn] = useState(choice?.basedOn ?? "");
  useEffect(() => {
    setName(choice?.name ?? "");
    setSize("");
    setAlign("");
    setBasedOn(choice?.basedOn ?? "");
  }, [choice?.id, choice?.name, choice?.basedOn, editor]);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (!choice) return;
        const paragraph: ParagraphFormatPatch = {};
        const alignment = (["left", "center", "right", "both"] as const).find(
          (value) => value === align,
        );
        if (alignment) paragraph.align = alignment;
        if (align === "inherit") paragraph.align = null;
        controller.run(async () => {
          await editor.updateStyle(choice.id, {
            character: size === "" ? {} : { size: Number(size) },
            paragraph,
            name,
            basedOn: basedOn || null,
          });
          setSize("");
          setAlign("");
          await refresh();
        });
      }}
    >
      <fieldset disabled={!choice || !!choice.reason}>
        <legend>{t.editStyle}</legend>
        <label>
          {t.styleName}
          <input
            aria-label={`${label}: ${t.styleName}`}
            required
            maxLength={200}
            value={name}
            onChange={(event) => setName(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.styleBasedOn}
          <select
            aria-label={`${label}: ${t.styleBasedOn}`}
            value={basedOn}
            onChange={(event) => setBasedOn(event.currentTarget.value)}
          >
            <option value="">{t.noBaseStyle}</option>
            {styles
              .filter((style) => style.id !== choice?.id)
              .map((style) => (
                <option
                  key={style.id}
                  value={style.id}
                  disabled={!!style.reason}
                >
                  {style.name}
                </option>
              ))}
          </select>
        </label>
        <label>
          {t.fontSize}
          <input
            aria-label={`${label}: ${t.fontSize}`}
            type="number"
            min={0.5}
            max={1024}
            step={0.5}
            placeholder={t.keepStyleProperty}
            value={size}
            onChange={(event) => setSize(event.currentTarget.value)}
          />
        </label>
        {kind === "paragraph" && (
          <label>
            {t.styleAlignment}
            <select
              aria-label={`${label}: ${t.styleAlignment}`}
              value={align}
              onChange={(event) => setAlign(event.currentTarget.value)}
            >
              <option value="">{t.keepStyleProperty}</option>
              <option value="inherit">{t.inheritStyleProperty}</option>
              <option value="left">{t.alignLeft}</option>
              <option value="center">{t.alignCenter}</option>
              <option value="right">{t.alignRight}</option>
              <option value="both">{t.alignJustify}</option>
            </select>
          </label>
        )}
        <button type="submit">
          {kind === "paragraph"
            ? t.updateParagraphStyle
            : t.updateCharacterStyle}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(async () => {
              if (!choice) return;
              await editor.updateStyle(choice.id, {
                character: { size: null },
                paragraph: {},
              });
              await refresh();
            })
          }
        >
          {t.restoreStyleSize}
        </button>
      </fieldset>
    </form>
  );
}
