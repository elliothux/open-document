import { useEffect, useMemo, useRef, useState } from "react";
import type { DocumentEditor, DocumentOverview } from "../web/editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { DocxBookmarks, bookmarkAtPosition } from "./docx-bookmarks.js";
import { DocxToc } from "./docx-toc.js";
import { DocxIndex } from "./docx-index.js";
import { DocxSources } from "./docx-sources.js";
import { Icon } from "@open-document/ui/icons";

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
  const section = useRef<HTMLElement>(null);
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
        const value = await editor.review.overview();
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
  const paragraphOrder = useMemo(
    () =>
      new Map(
        result?.bookmarkParagraphs.map(([id, story], index) => [
          id,
          { index, story },
        ]),
      ),
    [result],
  );
  const focus = stale || blocked ? undefined : snapshot.data.selection?.focus;
  const currentHeading =
    focus &&
    result?.headings.find(
      (heading) => heading.paragraph === focus.paragraph && !heading.reason,
    )?.paragraph;
  const currentBookmark =
    focus && result
      ? bookmarkAtPosition(result.bookmarks, focus, paragraphOrder)
      : undefined;
  useEffect(() => {
    const item = section.current?.querySelector(
      currentBookmark
        ? '.od-docx-bookmarks > [aria-current="location"]'
        : 'nav [aria-current="location"]',
    );
    const options: ScrollIntoViewOptions & { container: "nearest" } = {
      block: "nearest",
      container: "nearest",
    };
    item?.scrollIntoView(options);
  }, [currentBookmark, currentHeading]);
  return (
    <section ref={section} aria-label={t.documentOverview}>
      <h2>
        <Icon name="table-of-contents" />
        {t.documentOverview}
      </h2>
      {result && (
        <>
          <nav aria-label={t.documentHeadings}>
            <h3>
              <Icon name="list-nested" />
              {t.documentHeadings}
            </h3>
            <ol className="od-docx-reference-list">
              {result.headings.map((heading, index) => (
                <li
                  key={heading.paragraph}
                  aria-current={
                    heading.paragraph === currentHeading
                      ? "location"
                      : undefined
                  }
                >
                  <button
                    type="button"
                    aria-label={`${t.headingLevel} ${heading.level}: ${heading.text}`}
                    title={heading.reason || undefined}
                    disabled={disabled || blocked || stale || !!heading.reason}
                    onClick={() =>
                      controller.run(() =>
                        editor.review.selectHeading(result, index),
                      )
                    }
                  >
                    {`${heading.level}. ${heading.text}`}
                  </button>
                </li>
              ))}
            </ol>
          </nav>
          <DocxBookmarks
            controller={controller}
            editor={editor}
            result={result}
            current={currentBookmark}
            disabled={disabled || blocked || stale}
            t={t}
          />
          <dl aria-label={t.bodyStatistics}>
            <div>
              <dt>{t.wordCount}</dt>
              <dd>{result.statistics.words}</dd>
            </div>
            <div>
              <dt>{t.characterCount}</dt>
              <dd>{result.statistics.characters}</dd>
            </div>
            <div>
              <dt>{t.characterCountNoSpaces}</dt>
              <dd>{result.statistics.charactersNoSpaces}</dd>
            </div>
            <div>
              <dt>{t.nonemptyParagraphs}</dt>
              <dd>{result.statistics.paragraphs}</dd>
            </div>
          </dl>
          <p>{t.bodyStatisticsScope}</p>
          {result.statistics.reason && <p>{result.statistics.reason}</p>}
          {result.diagnostics.map((d) => (
            <p key={d}>{d}</p>
          ))}
          {result.truncated && <p>{t.headingsTruncated}</p>}
        </>
      )}
      <DocxSources
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        blocked={blocked}
      />
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
    </section>
  );
}
