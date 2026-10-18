import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxThemeColors,
  DocxThemeSlot,
  DocxThemeFonts,
  DocxThemeFontEdit,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxTheme({
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
  const [query, setQuery] = useState<DocxThemeColors>();
  const [slot, setSlot] = useState<DocxThemeSlot>("accent1");
  const selected = query?.colors.find((value) => value.slot === slot);
  const [color, setColor] = useState("#000000");
  useEffect(
    () => setColor(`#${selected?.color ?? "000000"}`),
    [slot, selected?.color],
  );
  const label = (slot: DocxThemeSlot) =>
    slot.startsWith("accent")
      ? `${t.accentColor} ${slot.slice(-1)}`
      : slot.startsWith("dk")
        ? `${t.darkColor} ${slot.slice(-1)}`
        : slot.startsWith("lt")
          ? `${t.lightColor} ${slot.slice(-1)}`
          : slot === "hlink"
            ? t.hyperlinkColor
            : t.followedHyperlinkColor;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(async () => {
          await editor.setThemeColor(slot, color.slice(1));
          setQuery(await editor.themeColors());
        });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.documentThemeColors}</legend>
        <p>{t.documentThemeScope}</p>
        <button
          type="button"
          onClick={() =>
            controller.run(async () => setQuery(await editor.themeColors()))
          }
        >
          {t.loadThemeColors}
        </button>
        <label>
          {t.themeColorSlot}
          <select
            value={slot}
            onChange={(event) => {
              const next = query?.colors.find(
                (value) => value.slot === event.currentTarget.value,
              );
              if (next) setSlot(next.slot);
            }}
          >
            {query?.colors.map((value) => (
              <option key={value.slot} value={value.slot}>
                {label(value.slot)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.themeColorValue}
          <input
            type="color"
            value={color}
            disabled={!selected || !!selected.reason}
            onChange={(event) => setColor(event.currentTarget.value)}
          />
        </label>
        {selected?.reason && <p role="status">{selected.reason}</p>}
        <button type="submit" disabled={!selected || !!selected.reason}>
          {t.applyThemeColor}
        </button>
      </fieldset>
    </form>
  );
}

export function DocxThemeFontsPanel({
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
  const [query, setQuery] = useState<DocxThemeFonts>();
  const [fonts, setFonts] = useState<DocxThemeFontEdit[]>([]);
  const load = async () => {
    const next = await editor.themeFonts();
    setQuery(next);
    setFonts(
      next.fonts.map(({ kind, script, font }) => ({
        kind,
        script,
        font: font ?? "",
      })),
    );
  };
  const editable = fonts.filter((font, i) => !query?.fonts[i]?.reason);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(async () => {
          await editor.setThemeFonts(editable);
          await load();
        });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.documentThemeFonts}</legend>
        <p>{t.documentThemeFontScope}</p>
        <button type="button" onClick={() => controller.run(load)}>
          {t.loadThemeFonts}
        </button>
        {fonts.map(({ kind, script, font }, i) => (
          <div key={`${kind}:${script}`}>
            <label>
              {kind === "major" ? t.headingFont : t.bodyFont}
              {script === "ea"
                ? ` (${t.eastAsianFont})`
                : script === "cs"
                  ? ` (${t.complexScriptFont})`
                  : ""}
              <input
                required={script === "latin"}
                maxLength={200}
                disabled={!!query?.fonts[i]?.reason}
                value={font}
                onChange={(event) =>
                  setFonts(
                    fonts.map((font, index) =>
                      index === i
                        ? { ...font, font: event.currentTarget.value }
                        : font,
                    ),
                  )
                }
              />
            </label>
            {query?.fonts[i]?.reason && (
              <span role="status">{query.fonts[i].reason}</span>
            )}
          </div>
        ))}
        {query && <p>{t.themeFontFallback}</p>}
        <button
          type="submit"
          disabled={
            !editable.length ||
            editable.some(
              ({ script, font }) => script === "latin" && !font.trim(),
            )
          }
        >
          {t.applyThemeFont}
        </button>
      </fieldset>
    </form>
  );
}
