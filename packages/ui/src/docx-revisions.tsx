import { useEffect, useState } from "react";
import type {
  DocumentEditor,
  DocumentRevisions,
} from "@open-document/web/editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxTracking } from "./docx-tracking.js";

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
    [kind, setKind] = useState("all"),
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
  const shown =
    result?.items.filter(
      (item) =>
        (author === null || item.author === author) &&
        (kind === "all" || item.kind === kind),
    ) ?? [];
  const kinds = {
    insert: t.revisionInsertion,
    delete: t.revisionDeletion,
    rowInsert: t.revisionRowInsertion,
    rowDelete: t.revisionRowDeletion,
    rowFormat: t.revisionRowFormat,
    characterFormat: t.revisionCharacterFormat,
    paragraphFormat: t.revisionParagraphFormat,
    unsupported: t.revisionUnsupported,
  };
  return (
    <section aria-label={t.docxRevisions}>
      <h3>{t.docxRevisions}</h3>
      <DocxTracking
        key={snapshot.documentId}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled || blocked}
      />
      <p>{t.revisionScope}</p>
      <p>{t.revisionDisplay}</p>
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
      <label>
        {t.revisionType}
        <select
          aria-label={t.revisionType}
          value={kind}
          onChange={(event) => setKind(event.currentTarget.value)}
        >
          <option value="all">{t.revisionAllTypes}</option>
          {Object.entries(kinds).map(([value, label]) => (
            <option value={value} key={value}>
              {label}
            </option>
          ))}
        </select>
      </label>
      {!stale && result.items.length === 0 && (
        <p role="status">{t.revisionNone}</p>
      )}
      {(["accept", "reject"] as const).map((action) => (
        <button
          key={action}
          type="button"
          disabled={
            disabled ||
            blocked ||
            stale ||
            !!result?.reason ||
            shown.length === 0 ||
            shown.some((item) => !!item.reason)
          }
          onClick={() => {
            if (!result) return;
            controller.run(() =>
              editor.resolveRevisions(result, {
                action,
                ids: shown.map((item) => item.id),
              }),
            );
          }}
        >
          {action === "accept" ? t.revisionAcceptShown : t.revisionRejectShown}
        </button>
      ))}
      <ol>
        {result &&
          shown.map((item) => (
            <li key={item.id}>
              <p>
                {kinds[item.kind]}: {item.author || t.revisionAnonymous}{" "}
                {item.date}
              </p>
              <p style={{ whiteSpace: "pre-wrap" }}>{item.text}</p>
              {item.reason && <p>{item.reason}</p>}
              <button
                type="button"
                disabled={disabled || !!blocked || stale || !!item.reason}
                onClick={() =>
                  controller.run(() => editor.showRevision(result, item.id))
                }
              >
                {t.revisionShow}
              </button>
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
