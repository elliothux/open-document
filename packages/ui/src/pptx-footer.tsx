import { useEffect, useState } from "react";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";

export function PptxFooter({ controller, state, file, disabled }: PanelProps) {
  const current = file.format === "pptx" ? file.editor.query.footer : undefined;
  const [dateOn, setDateOn] = useState(
    current?.date !== null && current?.date !== undefined,
  );
  const initialDate = current?.date;
  const settings =
    typeof initialDate === "object" && initialDate !== null
      ? initialDate
      : undefined;
  const [date, setDate] = useState(
    typeof initialDate === "string" ? initialDate : "",
  );
  const [automatic, setAutomatic] = useState(!!settings);
  const [format, setFormat] = useState(settings?.format ?? 1);
  const [language, setLanguage] = useState<"en-US" | "zh-CN" | "zh-TW">(
    settings?.language ?? "en-US",
  );
  const [footerOn, setFooterOn] = useState(
    current?.footer !== null && current?.footer !== undefined,
  );
  const [footer, setFooter] = useState(current?.footer ?? "");
  const [number, setNumber] = useState(current?.number ?? false);
  const sourceNumber =
    file.format === "pptx" ? file.editor.query.firstSlideNumber : 1;
  const [firstNumber, setFirstNumber] = useState(String(sourceNumber));
  useEffect(() => setFirstNumber(String(sourceNumber)), [sourceNumber]);
  if (file.format !== "pptx" || !current) return null;
  const editor = file.editor,
    t = messages(state.locale);
  const apply = (allSlides: boolean) =>
    controller.run(() =>
      editor.editSlides({
        action: "footer",
        value: {
          date: dateOn ? (automatic ? { format, language } : date) : null,
          footer: footerOn ? footer : null,
          number,
        },
        allSlides,
      }),
    );
  return (
    <>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editSlides({
              action: "firstSlideNumber",
              number: Number(firstNumber),
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !!editor.query.slideVisibilityReason}>
          <legend>{t.slideNumbering}</legend>
          <label>
            {t.firstSlideNumber}
            <input
              type="number"
              required
              min={0}
              max={0xffffffff}
              step={1}
              value={firstNumber}
              onChange={(event) => setFirstNumber(event.currentTarget.value)}
            />
          </label>
          <button type="submit">{t.applySlideNumbering}</button>
        </fieldset>
      </form>
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
            {t.slideDate}
          </label>
          {dateOn && (
            <>
              <label>
                <input
                  type="checkbox"
                  checked={automatic}
                  onChange={(event) =>
                    setAutomatic(event.currentTarget.checked)
                  }
                />
                {t.slideAutomaticDate}
              </label>
              {automatic ? (
                <>
                  <label>
                    {t.slideDateLanguage}
                    <select
                      value={language}
                      onChange={(event) => {
                        const value = event.currentTarget.value;
                        if (
                          value === "en-US" ||
                          value === "zh-CN" ||
                          value === "zh-TW"
                        )
                          setLanguage(value);
                      }}
                    >
                      <option value="en-US">English (United States)</option>
                      <option value="zh-CN">中文（简体）</option>
                      <option value="zh-TW">中文（繁體）</option>
                    </select>
                  </label>
                  <label>
                    {t.slideDateFormat}
                    <select
                      value={format}
                      onChange={(event) =>
                        setFormat(Number(event.currentTarget.value))
                      }
                    >
                      {(language === "en-US" ? englishDates : chineseDates).map(
                        (sample, index) => (
                          <option key={index} value={index + 1}>
                            {sample}
                          </option>
                        ),
                      )}
                    </select>
                  </label>
                </>
              ) : (
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
            </>
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
    </>
  );
}

const englishDates = [
  "2/29/2024",
  "Thursday, February 29, 2024",
  "29 February 2024",
  "February 29, 2024",
  "29-Feb-24",
  "February 24",
  "Feb-24",
  "2/29/2024 11:05 PM",
  "2/29/2024 11:05:09 PM",
  "23:05",
  "23:05:09",
  "11:05 PM",
  "11:05:09 PM",
];
const chineseDates = [
  "2024/2/29",
  "2024年2月29日",
  "2024年2月29日",
  "2024年2月29日星期W",
  "23时5分9秒",
  "2024年2月29日星期W",
  "2024年2月",
  "02/29/2024 11:05 下午",
  "02/29/2024 11:05:09 下午",
  "23:05",
  "23:05:09",
  "11:05 下午",
  "11:05:09: 下午",
];
