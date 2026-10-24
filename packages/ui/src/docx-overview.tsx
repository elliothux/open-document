import { useEffect, useState } from "react";
import type {
  DocumentEditor,
  DocumentOverview,
} from "@open-document/web/editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxBookmarks } from "./docx-bookmarks.js";
import { DocxToc } from "./docx-toc.js";
import { DocxIndex } from "./docx-index.js";

export function DocxOverview({
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
  const [result, setResult] = useState<DocumentOverview>();
  const blocked =
    !!state.document?.composition ||
    !!state.document?.dragging ||
    !!state.document?.paused ||
    !!state.document?.stopped;
  useEffect(() => {
    if (blocked) return;
    let active = true;
    controller.run(async () => {
      try {
        await editor.whenIdle();
        if (!active) return;
        const value = await editor.overview();
        if (active) setResult(value);
      } catch (error) {
        if (active) throw error;
      }
    });
    return () => {
      active = false;
    };
  }, [controller, editor, snapshot.documentId, snapshot.revision, blocked]);
  const stale =
    !result ||
    result.documentId !== snapshot.documentId ||
    result.revision !== snapshot.revision;
  return (
    <section aria-label={t.documentOverview}>
      <h2>{t.documentOverview}</h2>
      <DocxIndex
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        blocked={blocked}
      />
      <DocxToc
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        blocked={blocked}
      />
      {result && (
        <>
          <DocxBookmarks
            controller={controller}
            editor={editor}
            result={result}
            disabled={disabled || blocked || stale}
            t={t}
          />
          <dl aria-label={t.bodyStatistics}>
            <dt>{t.wordCount}</dt>
            <dd>{result.statistics.words}</dd>
            <dt>{t.characterCount}</dt>
            <dd>{result.statistics.characters}</dd>
            <dt>{t.characterCountNoSpaces}</dt>
            <dd>{result.statistics.charactersNoSpaces}</dd>
            <dt>{t.nonemptyParagraphs}</dt>
            <dd>{result.statistics.paragraphs}</dd>
          </dl>
          <p>{t.bodyStatisticsScope}</p>
          {result.statistics.reason && <p>{result.statistics.reason}</p>}
          {result.diagnostics.map((d) => (
            <p key={d}>{d}</p>
          ))}
          {result.truncated && <p>{t.headingsTruncated}</p>}
          <nav aria-label={t.documentHeadings}>
            <ol>
              {result.headings.map((heading, index) => (
                <li key={heading.paragraph}>
                  <button
                    type="button"
                    aria-label={`${t.headingLevel} ${heading.level}: ${heading.text}`}
                    title={heading.reason || undefined}
                    disabled={disabled || blocked || stale || !!heading.reason}
                    onClick={() =>
                      controller.run(() => editor.selectHeading(result, index))
                    }
                  >
                    {`${heading.level}. ${heading.text}`}
                  </button>
                </li>
              ))}
            </ol>
          </nav>
        </>
      )}
    </section>
  );
}
