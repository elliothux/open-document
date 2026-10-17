import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxRunningArea,
  DocxRunningKind,
  DocxRunningVariant,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxRunning({
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
  const [kind, setKind] = useState<DocxRunningKind>("header");
  const [variant, setVariant] = useState<DocxRunningVariant>("default");
  const [first, setFirst] = useState(false);
  const [even, setEven] = useState(false);
  const [area, setArea] = useState<DocxRunningArea>();
  const [text, setText] = useState("");
  const [distance, setDistance] = useState(36);
  const stale = area?.revision !== state.document?.revision;
  const load = async () => {
    const value = await editor.runningArea(kind, variant);
    setArea(value);
    setText(value.text);
    setDistance(value.distance);
    setFirst(value.differentFirst);
    setEven(value.differentEven);
  };
  return (
    <section aria-label={t.runningArea}>
      <h3>{t.runningArea}</h3>
      <label>
        {t.runningArea}
        <select
          disabled={disabled}
          value={kind}
          onChange={(event) => {
            setKind(
              event.currentTarget.value === "footer" ? "footer" : "header",
            );
            setArea(undefined);
          }}
        >
          <option value="header">{t.header}</option>
          <option value="footer">{t.footer}</option>
        </select>
      </label>
      <label>
        {t.runningVariant}
        <select
          disabled={disabled}
          value={variant}
          onChange={(event) => {
            const value = event.currentTarget.value;
            setVariant(
              value === "first" || value === "even" ? value : "default",
            );
            setArea(undefined);
          }}
        >
          <option value="default">{t.runningDefault}</option>
          <option value="first">
            {kind === "header" ? t.firstHeader : t.firstFooter}
          </option>
          <option value="even">
            {kind === "header" ? t.evenHeader : t.evenFooter}
          </option>
        </select>
      </label>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.loadRunningArea}
      </button>
      {area && (
        <button
          type="button"
          disabled={disabled || stale || !area.shared}
          onClick={() =>
            controller.run(async () => {
              await editor.unlinkRunningArea(kind, variant);
              await load();
            })
          }
        >
          {t.unlinkRunningArea}
        </button>
      )}
      {area && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setRunningArea(kind, variant, text, distance);
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || !!area.reason}>
            <label>
              <input
                type="checkbox"
                checked={first}
                onChange={(event) => setFirst(event.currentTarget.checked)}
              />
              {t.headerDifferentFirst}
            </label>
            <label>
              <input
                type="checkbox"
                checked={even}
                onChange={(event) => setEven(event.currentTarget.checked)}
              />
              {t.headerDifferentOddEven}
            </label>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.setRunningOptions(first, even);
                  const value = await editor.runningArea(kind, variant);
                  setArea(value);
                  setFirst(value.differentFirst);
                  setEven(value.differentEven);
                })
              }
            >
              {t.applyRunningOptions}
            </button>
            <label>
              {kind === "header" ? t.header : t.footer}
              <textarea
                maxLength={8192}
                value={text}
                onChange={(event) => setText(event.currentTarget.value)}
              />
            </label>
            <label>
              {kind === "header" ? t.headerDistance : t.footerDistance}
              <input
                type="number"
                min={0}
                max={14400}
                step={0.05}
                required
                value={Number.isFinite(distance) ? distance : ""}
                onChange={(event) =>
                  setDistance(event.currentTarget.valueAsNumber)
                }
              />
            </label>
            <button type="submit">{t.apply}</button>
          </fieldset>
          {area.reason && <p>{area.reason}</p>}
          {stale && <p>{t.reloadPageSetup}</p>}
        </form>
      )}
    </section>
  );
}
