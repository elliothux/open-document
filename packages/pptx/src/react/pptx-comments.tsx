import { useEffect, useState } from "react";
import {
  checkPptxSlideEdit,
  type PptxComment,
  type PptxSlideEdit,
} from "../web/pptx.js";
import type { PanelProps } from "./panels.js";
import { messages } from "@open-document/ui/messages";

export function PptxComments(props: PanelProps) {
  const { controller, state, file, disabled } = props;
  const [text, setText] = useState("");
  const [parent, setParent] = useState<string | null>(null);
  const [error, setError] = useState("");
  const comments =
    file.format === "pptx" ? file.editor.query.comments : undefined;
  useEffect(() => {
    if (parent && !comments?.items.some((item) => item.id === parent))
      setParent(null);
  }, [comments, parent]);
  if (file.format !== "pptx" || !comments) return null;
  const editor = file.editor,
    slide = editor.query.slide,
    t = messages(state.locale);
  const author = controller.options.commentAuthor;
  const roots = comments.items.filter((item) => item.parent === null);
  return (
    <fieldset disabled={disabled || !!comments.reason}>
      <legend>{t.slideComments}</legend>
      {comments.reason && <p>{comments.reason}</p>}
      <ul>
        {roots.map((root) => (
          <li key={root.id}>
            <CommentEntry key={root.id + root.text} {...props} entry={root} />
            {root.status !== null && (
              <button
                type="button"
                onClick={() =>
                  controller.run(() =>
                    editor.editSlides(
                      {
                        action: "commentStatus",
                        id: root.id,
                        status:
                          root.status === "active" ? "resolved" : "active",
                      },
                      slide,
                    ),
                  )
                }
              >
                {root.status === "active" ? t.commentResolve : t.commentReopen}
              </button>
            )}
            <button
              type="button"
              disabled={!author}
              onClick={() => setParent(root.id)}
            >
              {t.commentReply}
            </button>
            <ul>
              {comments.items
                .filter((item) => item.parent === root.id)
                .map((reply) => (
                  <li key={reply.id}>
                    <CommentEntry
                      key={reply.id + reply.text}
                      {...props}
                      entry={reply}
                    />
                  </li>
                ))}
            </ul>
          </li>
        ))}
      </ul>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (!author) return;
          const change: PptxSlideEdit = {
            action: "commentAdd",
            text,
            author,
            date: new Date().toISOString(),
            parent,
          };
          try {
            checkPptxSlideEdit(change);
          } catch (error) {
            setError(String(error));
            return;
          }
          setError("");
          controller.run(async () => {
            await editor.editSlides(change, slide);
            setText("");
            setParent(null);
          });
        }}
      >
        {parent && (
          <p>
            {comments.items.find((item) => item.id === parent)?.text}
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
        <button type="submit" disabled={!author || !text.trim()}>
          {parent ? t.commentReply : t.commentAdd}
        </button>
      </form>
      {!author && <p>{t.commentAuthorRequired}</p>}
      {error && <p role="alert">{error}</p>}
    </fieldset>
  );
}

function CommentEntry({
  controller,
  state,
  file,
  entry,
}: PanelProps & { entry: PptxComment }) {
  const [text, setText] = useState(entry.text);
  const [error, setError] = useState("");
  if (file.format !== "pptx") return null;
  const editor = file.editor,
    slide = editor.query.slide,
    t = messages(state.locale);
  return (
    <article aria-label={entry.id}>
      <p>
        {entry.author}
        {entry.date && (
          <>
            {" "}
            <time dateTime={entry.date}>{entry.date}</time>
          </>
        )}
      </p>
      {entry.status === "resolved" && <p>{t.commentResolved}</p>}
      {entry.status === "closed" && <p>{t.commentClosed}</p>}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const change: PptxSlideEdit = {
            action: "commentUpdate",
            id: entry.id,
            text,
          };
          try {
            checkPptxSlideEdit(change);
          } catch (error) {
            setError(String(error));
            return;
          }
          setError("");
          controller.run(() => editor.editSlides(change, slide));
        }}
      >
        <label>
          {t.commentText}
          <textarea
            aria-label={t.commentText}
            value={text}
            maxLength={32767}
            onChange={(event) => setText(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={!text.trim() || text === entry.text}>
          {t.commentUpdate}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(() =>
              editor.editSlides(
                { action: "commentRemove", id: entry.id },
                slide,
              ),
            )
          }
        >
          {t.commentRemove}
        </button>
      </form>
      {error && <p role="alert">{error}</p>}
    </article>
  );
}
