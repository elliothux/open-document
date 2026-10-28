import { useState } from "react";
import type { DocumentEditor, DocumentSearchResult } from "../web/editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxSearch({
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
  const t = messages(state.locale),
    snapshot = editor.getSnapshot();
  const [text, setText] = useState(""),
    [replacement, setReplacement] = useState(""),
    [matchCase, setMatchCase] = useState(false),
    [wholeWord, setWholeWord] = useState(false),
    [result, setResult] = useState<DocumentSearchResult>(),
    [selected, setSelected] = useState(0);
  disabled ||= snapshot.stopped;
  const stale =
    !!result &&
    (result.documentId !== snapshot.documentId ||
      result.revision !== snapshot.revision);
  const changeQuery = () => setResult(undefined);
  const find = () =>
    controller.run(async () => {
      const found = await editor.find(text, { matchCase, wholeWord });
      setResult(found);
      setSelected(0);
    });
  return (
    <section aria-label={t.findReplace}>
      <h2>{t.findReplace}</h2>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (text) find();
        }}
      >
        <label>
          {t.findText}
          <input
            type="search"
            maxLength={65536}
            value={text}
            disabled={disabled}
            onChange={(event) => {
              setText(event.currentTarget.value);
              changeQuery();
            }}
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={matchCase}
            disabled={disabled}
            onChange={(event) => {
              setMatchCase(event.currentTarget.checked);
              changeQuery();
            }}
          />
          {t.matchCase}
        </label>
        <label>
          <input
            type="checkbox"
            checked={wholeWord}
            disabled={disabled}
            onChange={(event) => {
              setWholeWord(event.currentTarget.checked);
              changeQuery();
            }}
          />
          {t.wholeWord}
        </label>
        <button type="submit" disabled={disabled || !text}>
          {t.find}
        </button>
      </form>
      <label>
        {t.replaceWith}
        <input
          value={replacement}
          maxLength={65536}
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
                disabled={disabled || stale || !!item.reason}
                aria-current={selected === index ? "true" : undefined}
                onClick={() =>
                  controller.run(async () => {
                    await editor.selectMatch(result, index);
                    setSelected(index);
                  })
                }
              >
                {index + 1}. {item.snippet}
              </button>
              {item.reason && <span>{item.reason}</span>}
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
