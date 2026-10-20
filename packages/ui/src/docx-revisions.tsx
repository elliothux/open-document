import { useEffect, useState } from "react";
import type {
  DocumentEditor,
  DocumentRevisions,
} from "@open-document/web/editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxRevisions({
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
  const [result, setResult] = useState<DocumentRevisions>(),
    [author, setAuthor] = useState<string | null>(null),
    [error, setError] = useState("");
  const blocked =
    !!snapshot.composition ||
    snapshot.dragging ||
    snapshot.paused ||
    snapshot.stopped;
  useEffect(() => {
    if (blocked) return;
    let active = true;
    controller.run(async () => {
      try {
        const value = await editor.revisions();
        if (active) {
          setResult(value);
          setError("");
        }
      } catch (error) {
        if (active)
          setError(error instanceof Error ? error.message : String(error));
      }
    });
    return () => {
      active = false;
    };
  }, [controller, editor, snapshot.documentId, snapshot.revision, blocked]);
  const authors = Array.from(
    new Set(result?.items.map((item) => item.author) ?? []),
  );
  useEffect(() => {
    if (
      author !== null &&
      result &&
      !result.items.some((item) => item.author === author)
    )
      setAuthor(null);
  }, [author, result]);
  const stale =
    !result ||
    result.documentId !== snapshot.documentId ||
    result.revision !== snapshot.revision;
  return (
    <section aria-label={t.docxRevisions}>
      <h3>{t.docxRevisions}</h3>
      <p>{t.revisionScope}</p>
      {error && <p role="alert">{error}</p>}
      {result?.reason && <p role="status">{result.reason}</p>}
      <label>
        {t.revisionAuthor}
        <select
          aria-label={t.revisionAuthor}
          value={author === null ? "all" : String(authors.indexOf(author))}
          onChange={(event) =>
            setAuthor(
              event.currentTarget.value === "all"
                ? null
                : (authors[Number(event.currentTarget.value)] ?? null),
            )
          }
        >
          <option value="all">{t.revisionAllAuthors}</option>
          {authors.map((value, index) => (
            <option value={index} key={value}>
              {value || t.revisionAnonymous}
            </option>
          ))}
        </select>
      </label>
      {!stale && result.items.length === 0 && (
        <p role="status">{t.revisionNone}</p>
      )}
      <ol>
        {result?.items
          .filter((item) => author === null || item.author === author)
          .map((item) => (
            <li key={item.id}>
              <p>
                {item.kind === "insert"
                  ? t.revisionInsertion
                  : item.kind === "delete"
                    ? t.revisionDeletion
                    : item.element}
                : {item.author || t.revisionAnonymous} {item.date}
              </p>
              <p style={{ whiteSpace: "pre-wrap" }}>{item.text}</p>
              {item.reason && <p>{item.reason}</p>}
              {(["accept", "reject"] as const).map((action) => (
                <button
                  key={action}
                  type="button"
                  disabled={
                    disabled ||
                    !!blocked ||
                    stale ||
                    !!result.reason ||
                    !!item.reason
                  }
                  onClick={() => {
                    controller.run(() =>
                      editor.resolveRevisions(result, {
                        action,
                        ids: [item.id],
                      }),
                    );
                  }}
                >
                  {action === "accept" ? t.revisionAccept : t.revisionReject}
                </button>
              ))}
            </li>
          ))}
      </ol>
    </section>
  );
}
