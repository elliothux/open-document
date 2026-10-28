import { useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import { listFormats, type DocxCaption } from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxCaption({
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
  const [label, setLabel] = useState(
    state.locale === "zh-CN" ? "图" : "Figure",
  );
  const [text, setText] = useState("");
  const [position, setPosition] = useState<DocxCaption["position"]>("after");
  const [format, setFormat] = useState<DocxCaption["format"]>("decimal");
  const [chapterLevel, setChapterLevel] = useState(0);
  const [separator, setSeparator] = useState("-");
  return (
    <section aria-label={t.caption}>
      <h4>{t.caption}</h4>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.insertCaption({
              label,
              text,
              position,
              format,
              ...(chapterLevel
                ? { chapter: { level: chapterLevel, separator } }
                : {}),
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !editor.getSnapshot().data.selection}>
          <label>
            {t.captionLabel}
            <input
              value={label}
              maxLength={40}
              required
              onChange={(event) => setLabel(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.captionText}
            <input
              value={text}
              maxLength={1024}
              onChange={(event) => setText(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.captionPosition}
            <select
              value={position}
              onChange={(event) => {
                if (
                  event.currentTarget.value === "before" ||
                  event.currentTarget.value === "after"
                )
                  setPosition(event.currentTarget.value);
              }}
            >
              <option value="before">{t.captionBefore}</option>
              <option value="after">{t.captionAfter}</option>
            </select>
          </label>
          <label>
            {t.captionFormat}
            <select
              value={format}
              onChange={(event) => {
                const value = event.currentTarget.value;
                if (
                  value === "decimal" ||
                  value === "lowerRoman" ||
                  value === "upperRoman" ||
                  value === "lowerLetter" ||
                  value === "upperLetter"
                )
                  setFormat(value);
              }}
            >
              {listFormats
                .filter(
                  (value) => value !== "bullet" && value !== "decimalZero",
                )
                .map((value) => (
                  <option key={value} value={value}>
                    {value}
                  </option>
                ))}
            </select>
          </label>
          <label>
            {t.captionChapterLevel}
            <select
              value={chapterLevel}
              onChange={(event) =>
                setChapterLevel(Number(event.currentTarget.value))
              }
            >
              <option value={0}>{t.captionChapterNone}</option>
              {Array.from({ length: 9 }, (_, i) => (
                <option key={i + 1} value={i + 1}>
                  {i + 1}
                </option>
              ))}
            </select>
          </label>
          {chapterLevel > 0 && (
            <label>
              {t.captionChapterSeparator}
              <select
                value={separator}
                onChange={(event) => setSeparator(event.currentTarget.value)}
              >
                {["-", ".", ":", "–", "—"].map((value) => (
                  <option key={value} value={value}>
                    {value}
                  </option>
                ))}
              </select>
            </label>
          )}
          <button type="submit">{t.insertCaption}</button>
        </fieldset>
      </form>
    </section>
  );
}
