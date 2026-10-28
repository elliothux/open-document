import { useEffect, useId, useState } from "react";
import type { PptxThemeSlot } from "../web/pptx.js";
import type { PanelProps } from "./panels.js";
import { messages } from "@open-document/ui/messages";

export function PptxTheme({ controller, state, file, disabled }: PanelProps) {
  const colors = file.format === "pptx" ? file.editor.query.themeColors : [];
  const [slot, setSlot] = useState<PptxThemeSlot>("accent1");
  const selected = colors.find((color) => color.slot === slot);
  const [color, setColor] = useState(`#${selected?.color ?? "000000"}`);
  useEffect(() => {
    setColor(`#${selected?.color ?? "000000"}`);
  }, [slot, selected?.color]);
  if (file.format !== "pptx" || !selected) return null;
  const editor = file.editor,
    t = messages(state.locale);
  const label = (slot: PptxThemeSlot) =>
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
        controller.run(() =>
          editor.editSlides({
            action: "themeColor",
            slot,
            color: color.slice(1),
          }),
        );
      }}
    >
      <fieldset disabled={disabled || !!editor.query.slideVisibilityReason}>
        <legend>{t.themeColors}</legend>
        <p>{t.themeColorScope}</p>
        <label>
          {t.themeColorSlot}
          <select
            value={slot}
            onChange={(event) => {
              const next = colors.find(
                (color) => color.slot === event.currentTarget.value,
              );
              if (next) setSlot(next.slot);
            }}
          >
            {colors.map((color) => (
              <option key={color.slot} value={color.slot}>
                {label(color.slot)}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.solidColor}
          <input
            type="color"
            value={color}
            onChange={(event) => setColor(event.currentTarget.value)}
          />
        </label>
        {selected.color === null && !selected.reason && <p>{t.mixed}</p>}
        {selected.reason && <p role="status">{selected.reason}</p>}
        <button type="submit" disabled={!!selected.reason}>
          {t.applyThemeColor}
        </button>
      </fieldset>
    </form>
  );
}

export function PptxThemeFonts({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const fonts = file.format === "pptx" ? file.editor.query.themeFonts : [];
  const scriptList = useId();
  const [kind, setKind] = useState<"major" | "minor">("major");
  const [script, setScript] = useState("latin");
  const selected = fonts.find(
    (value) => value.kind === kind && value.script === script,
  );
  const [font, setFont] = useState(selected?.font ?? "");
  useEffect(() => {
    setFont(selected?.font ?? "");
  }, [kind, script, selected?.font]);
  if (file.format !== "pptx") return null;
  const editor = file.editor,
    t = messages(state.locale);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSlides({ action: "themeFont", kind, script, font }),
        );
      }}
    >
      <fieldset disabled={disabled || !!editor.query.slideVisibilityReason}>
        <legend>{t.themeFonts}</legend>
        <p>{t.themeColorScope}</p>
        <label>
          {t.themeFontRole}
          <select
            value={kind}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "major" || value === "minor") setKind(value);
            }}
          >
            <option value="major">{t.headingFont}</option>
            <option value="minor">{t.bodyFont}</option>
          </select>
        </label>
        <label>
          {t.themeFontScript}
          <input
            value={script}
            list={scriptList}
            pattern="latin|ea|cs|[A-Z][a-z]{3}"
            required
            onChange={(event) => setScript(event.currentTarget.value)}
          />
        </label>
        <datalist id={scriptList}>
          {fonts
            .filter((value) => value.kind === kind)
            .map((value) => (
              <option key={value.script} value={value.script}>
                {value.script === "latin"
                  ? t.latinFont
                  : value.script === "ea"
                    ? t.eastAsianFont
                    : value.script === "cs"
                      ? t.complexScriptFont
                      : value.script}
              </option>
            ))}
        </datalist>
        <label>
          {t.fontFamily}
          <input
            value={font}
            maxLength={200}
            required={script === "latin"}
            onChange={(event) => setFont(event.currentTarget.value)}
          />
        </label>
        {script !== "latin" && <p>{t.themeFontFallback}</p>}
        {selected?.font === null && !selected.reason && <p>{t.mixed}</p>}
        {selected?.reason && <p role="status">{selected.reason}</p>}
        <button type="submit" disabled={!!selected?.reason}>
          {t.applyThemeFont}
        </button>
      </fieldset>
    </form>
  );
}
