import { useEffect, useRef, useState } from "react";
import type {
  DocumentComments,
  DocumentEditor,
} from "@open-document/web/editor";
import {
  checkDocxComment,
  type DocxCommentEdit,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxComments({
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
  const [result, setResult] = useState<DocumentComments>();
  const [text, setText] = useState("");
  const [error, setError] = useState("");
  const [parent, setParent] = useState<string | null>(null);
  const panel = useRef<HTMLElement>(null);
  const shown = useRef<Readonly<{ id: string }> | undefined>(undefined);
  const focus = editor.getCommentFocus();
  useEffect(() => {
    if (
      parent &&
      result &&
      !result.items.some((item) => item.id === parent && item.parent === null)
    )
      setParent(null);
  }, [parent, result]);
  const blocked =
    !!snapshot.composition ||
    !!snapshot.dragging ||
    !!snapshot.paused ||
    !!snapshot.stopped;
  useEffect(() => {
    if (blocked) return;
    let active = true;
    controller.run(async () => {
      try {
        const value = await editor.comments();
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
  useEffect(() => {
    if (!focus || shown.current === focus || stale || blocked || snapshot.busy)
      return;
    const entry = Array.from(
      panel.current?.querySelectorAll<HTMLElement>("[data-comment-id]") ?? [],
    ).find((item) => item.dataset.commentId === focus.id);
    if (entry) {
      entry.scrollIntoView({ block: "nearest" });
      shown.current = focus;
    }
  }, [focus, stale, blocked, snapshot.busy, result]);
  const apply = (change: DocxCommentEdit, done?: () => void) => {
    try {
      checkDocxComment(change);
    } catch (error) {
      setError(String(error));
      return;
    }
    setError("");
    controller.run(async () => {
      await editor.editComment(change);
      done?.();
    });
  };
  const author = controller.options.commentAuthor;
  return (
    <section ref={panel} aria-label={t.docxComments}>
      <h2>{t.docxComments}</h2>
      {editor.layout.comments.reason &&
        editor.layout.comments.reason !== result?.reason && (
          <p>{editor.layout.comments.reason}</p>
        )}
      <fieldset disabled={disabled || blocked || stale || !!result?.reason}>
        <legend>{t.docxComments}</legend>
        {result?.reason && <p>{result.reason}</p>}
        {(["previous", "next"] as const).map((direction) => (
          <button
            key={direction}
            type="button"
            disabled={
              !result?.items.some(
                (item) =>
                  item.parent === null &&
                  !item.done &&
                  !item.reason &&
                  item.selection,
              )
            }
            onClick={() =>
              controller.run(() => editor.navigateComment(direction))
            }
          >
            {direction === "previous" ? t.commentPrevious : t.commentNext}
          </button>
        ))}
        <form
          onSubmit={(event) => {
            event.preventDefault();
            if (!author) return;
            const selection = editor.getSnapshot().data.selection;
            const content = {
              text,
              author: author.name,
              initials: author.initials,
              date: new Date().toISOString(),
            };
            if (parent)
              apply({ action: "reply", id: parent, ...content }, () => {
                setText("");
                setParent(null);
              });
            else if (selection)
              apply(
                {
                  action:
                    selection.anchor.paragraph === selection.focus.paragraph &&
                    selection.anchor.offset === selection.focus.offset
                      ? "addWord"
                      : "add",
                  ...content,
                  selection,
                },
                () => setText(""),
              );
          }}
        >
          {parent && (
            <p>
              {result?.items.find((item) => item.id === parent)?.text}
              <button type="button" onClick={() => setParent(null)}>
                {t.cancel}
              </button>
            </p>
          )}
          <label>
            {parent ? t.commentReplyText : t.commentText}
            <textarea
              aria-label={parent ? t.commentReplyText : t.commentText}
              value={text}
              maxLength={32767}
              disabled={!author}
              onChange={(event) => setText(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={
              !author || !text.trim() || (!parent && !snapshot.data.selection)
            }
          >
            {parent ? t.commentReply : t.commentAdd}
          </button>
        </form>
        {!author && <p>{t.localCommentAuthorRequired}</p>}
        <ul>
          {result?.items
            .filter((item) => item.parent === null)
            .map((comment) => (
              <li key={comment.id}>
                <CommentEntry
                  comment={comment}
                  state={state}
                  apply={apply}
                  active={focus?.id === comment.id}
                />
                <button
                  type="button"
                  disabled={!author || !!comment.reason}
                  onClick={() => setParent(comment.id)}
                >
                  {t.commentReply}
                </button>
                <button
                  type="button"
                  disabled={!!comment.reason}
                  onClick={() =>
                    apply({
                      action: "resolve",
                      id: comment.id,
                      done: !comment.done,
                    })
                  }
                >
                  {comment.done ? t.commentReopen : t.commentResolve}
                </button>
                {comment.done && <p>{t.commentResolved}</p>}
                <ul>
                  {result.items
                    .filter((reply) => reply.parent === comment.id)
                    .map((reply) => (
                      <li key={reply.id}>
                        <CommentEntry
                          comment={reply}
                          state={state}
                          apply={apply}
                          active={focus?.id === reply.id}
                        />
                      </li>
                    ))}
                </ul>
              </li>
            ))}
        </ul>
      </fieldset>
      {error && <p role="alert">{error}</p>}
    </section>
  );
}

function CommentEntry({
  comment,
  state,
  apply,
  active,
}: {
  comment: DocumentComments["items"][number];
  state: UiSnapshot;
  apply(change: DocxCommentEdit): void;
  active: boolean;
}) {
  const [text, setText] = useState(comment.text);
  useEffect(() => setText(comment.text), [comment.text]);
  const t = messages(state.locale);
  return (
    <article
      data-comment-id={comment.id}
      aria-current={active ? "true" : undefined}
      aria-label={`${t.commentItem} ${comment.id}`}
    >
      <p>
        {comment.author} {comment.initials}{" "}
        {comment.date && <time dateTime={comment.date}>{comment.date}</time>}
      </p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          apply({ action: "update", id: comment.id, text });
        }}
      >
        <fieldset disabled={!!comment.reason}>
          <legend>{`${t.commentItem} ${comment.id}`}</legend>
          <label>
            {t.commentText}
            <textarea
              aria-label={t.commentText}
              value={text}
              maxLength={32767}
              onChange={(event) => setText(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={!text.trim() || text === comment.text}
          >
            {t.commentUpdate}
          </button>
          <button
            type="button"
            onClick={() => apply({ action: "goTo", id: comment.id })}
          >
            {t.commentGoTo}
          </button>
          <button
            type="button"
            onClick={() => apply({ action: "remove", id: comment.id })}
          >
            {comment.parent === null ? t.commentRemove : t.commentRemoveSingle}
          </button>
        </fieldset>
      </form>
      {comment.reason && <p>{comment.reason}</p>}
    </article>
  );
}
