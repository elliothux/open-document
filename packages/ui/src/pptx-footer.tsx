import { useState } from "react";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";

export function PptxFooter({ controller, state, file, disabled }: PanelProps) {
  const current = file.format === "pptx" ? file.editor.query.footer : undefined;
  const [dateOn, setDateOn] = useState(
    current?.date !== null && current?.date !== undefined,
  );
  const [date, setDate] = useState(current?.date ?? "");
  const [footerOn, setFooterOn] = useState(
    current?.footer !== null && current?.footer !== undefined,
  );
  const [footer, setFooter] = useState(current?.footer ?? "");
  const [number, setNumber] = useState(current?.number ?? false);
  if (file.format !== "pptx" || !current) return null;
  const editor = file.editor,
    t = messages(state.locale);
  const apply = (allSlides: boolean) =>
    controller.run(() =>
      editor.editSlides({
        action: "footer",
        value: {
          date: dateOn ? date : null,
          footer: footerOn ? footer : null,
          number,
        },
        allSlides,
      }),
    );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply(false);
      }}
    >
      <fieldset disabled={disabled || !!current.reason}>
        <legend>{t.slideFooter}</legend>
        <label>
          <input
            type="checkbox"
            checked={dateOn}
            onChange={(event) => setDateOn(event.currentTarget.checked)}
          />
          {t.slideFixedDate}
        </label>
        {dateOn && (
          <label>
            {t.slideDateText}
            <input
              type="text"
              maxLength={4096}
              value={date}
              onChange={(event) => setDate(event.currentTarget.value)}
            />
          </label>
        )}
        <label>
          <input
            type="checkbox"
            checked={number}
            onChange={(event) => setNumber(event.currentTarget.checked)}
          />
          {t.slideNumber}
        </label>
        <label>
          <input
            type="checkbox"
            checked={footerOn}
            onChange={(event) => setFooterOn(event.currentTarget.checked)}
          />
          {t.slideFooterText}
        </label>
        {footerOn && (
          <label>
            {t.slideFooterValue}
            <input
              type="text"
              maxLength={4096}
              value={footer}
              onChange={(event) => setFooter(event.currentTarget.value)}
            />
          </label>
        )}
        <button type="submit">{t.applySlideFooter}</button>
        <button type="button" onClick={() => apply(true)}>
          {t.applyAllSlideFooters}
        </button>
      </fieldset>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(() => editor.refreshDateFields())}
      >
        {t.refreshSlideDates}
      </button>
      {current.reason && <p>{current.reason}</p>}
    </form>
  );
}
