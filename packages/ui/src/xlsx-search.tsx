import { useState } from "react";
import type {
  SpreadsheetEditor,
  SpreadsheetSearchResult,
} from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxSearch({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    snapshot = editor.getSnapshot();
  const [text, setText] = useState(""),
    [replacement, setReplacement] = useState("");
  const [options, setOptions] = useState({
    matchCase: false,
    wholeCell: false,
    formulas: true,
    workbook: false,
  });
  const [result, setResult] = useState<SpreadsheetSearchResult>(),
    [selected, setSelected] = useState(0);
  disabled ||= snapshot.stopped || snapshot.composition;
  const stale =
    !!result &&
    (result.documentId !== snapshot.documentId ||
      result.revision !== snapshot.revision);
  return (
    <section aria-label={t.findReplace}>
      <h2>{t.findReplace}</h2>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (text)
            controller.run(async () => {
              setResult(await editor.find(text, options));
              setSelected(0);
            });
        }}
      >
        <label>
          {t.findText}
          <input
            type="search"
            value={text}
            maxLength={32767}
            disabled={disabled}
            onChange={(event) => {
              setText(event.currentTarget.value);
              setResult(undefined);
            }}
          />
        </label>
        {(
          [
            ["matchCase", t.matchCase],
            ["wholeCell", t.wholeCell],
            ["formulas", t.searchFormulas],
            ["workbook", t.searchWorkbook],
          ] as const
        ).map(([key, label]) => (
          <label key={key}>
            <input
              type="checkbox"
              checked={options[key]}
              disabled={disabled}
              onChange={(event) => {
                setOptions({ ...options, [key]: event.currentTarget.checked });
                setResult(undefined);
              }}
            />
            {label}
          </label>
        ))}
        <button type="submit" disabled={disabled || !text}>
          {t.find}
        </button>
      </form>
      <label>
        {t.replaceWith}
        <input
          value={replacement}
          maxLength={32767}
          disabled={disabled}
          onChange={(event) => setReplacement(event.currentTarget.value)}
        />
      </label>
      <button
        type="button"
        disabled={
          disabled ||
          stale ||
          !result?.matches[selected] ||
          !!result.matches[selected]?.reason
        }
        onClick={() =>
          result &&
          controller.run(() =>
            editor.replaceMatches(result, replacement, selected),
          )
        }
      >
        {t.replaceMatch}
      </button>
      <button
        type="button"
        disabled={
          disabled ||
          stale ||
          !result?.matches.length ||
          result.truncated ||
          result.matches.some((item) => !!item.reason)
        }
        onClick={() =>
          result &&
          controller.run(() => editor.replaceMatches(result, replacement))
        }
      >
        {t.replaceAll}
      </button>
      <p role="status">
        {stale
          ? t.searchStale
          : result
            ? `${t.matches}: ${result.matches.length}${result.truncated ? ` — ${t.searchLimit}` : ""}`
            : ""}
      </p>
      {result && (
        <ol aria-label={t.matches}>
          {result.matches.map((item, index) => (
            <li key={index}>
              <button
                type="button"
                disabled={disabled || stale || item.hidden}
                aria-current={selected === index ? "true" : undefined}
                onClick={() =>
                  controller.run(async () => {
                    await editor.selectMatch(result, index);
                    setSelected(index);
                  })
                }
              >
                {item.name}!{item.address}: {item.snippet}
              </button>
              {item.hidden && <span>{t.hiddenSheet}</span>}
              {item.reason && <span>{item.reason}</span>}
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
