import { useEffect, useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import type { XlsxThreads, XlsxThreadEdit } from "../web/xlsx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function XlsxComments({
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
    query = editor.currentState;
  const [catalog, setCatalog] = useState<XlsxThreads>();
  const [text, setText] = useState("");
  const snapshot = editor.getSnapshot();
  const blocked =
    snapshot.composition ||
    snapshot.paused ||
    snapshot.stopped ||
    snapshot.draft;
  const selection = query.selection.address;
  useEffect(() => {
    if (blocked) return;
    let active = true;
    controller.run(async () => {
      await editor.whenIdle();
      if (!active) return;
      const result = await editor.threads();
      if (active) setCatalog(result);
    });
    return () => {
      active = false;
    };
  }, [controller, editor, query.revision, query.sheet, selection, blocked]);
  useEffect(() => setText(""), [editor, query.sheet, selection]);
  const stale =
    !catalog ||
    catalog.revision !== query.revision ||
    catalog.sheet !== query.sheet ||
    catalog.cell !== query.note.address;
  const root = catalog?.items.find((item) => item.parentId === null);
  const author = controller.options.commentAuthor?.name;
  const apply = (change: XlsxThreadEdit) =>
    controller.run(() => editor.editThread(change));
  return (
    <fieldset disabled={disabled || !!blocked || stale || !!catalog?.reason}>
      <legend>{t.cellComments}</legend>
      <p>{catalog?.cell}</p>
      {catalog?.reason && <p>{catalog.reason}</p>}
      {root?.resolved && <p>{t.commentResolved}</p>}
      {catalog?.items.map((item) => (
        <Message key={item.id} item={item} state={state} apply={apply} />
      ))}
      {root && (
        <button
          type="button"
          onClick={() =>
            apply({ action: "resolve", id: root.id, resolved: !root.resolved })
          }
        >
          {root.resolved ? t.commentReopen : t.commentResolve}
        </button>
      )}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (!author || !catalog || !text.trim()) return;
          const content = { text, author, date: new Date().toISOString() };
          controller.run(async () => {
            await editor.editThread(
              root
                ? { action: "reply", id: root.id, ...content }
                : { action: "create", cell: catalog.cell, ...content },
            );
            setText("");
          });
        }}
      >
        <label>
          {root ? t.commentReplyText : t.commentText}
          <textarea
            aria-label={root ? t.commentReplyText : t.commentText}
            value={text}
            maxLength={32767}
            disabled={!author || root?.resolved}
            onChange={(event) => setText(event.currentTarget.value)}
          />
        </label>
        <button
          type="submit"
          disabled={!author || !text.trim() || root?.resolved}
        >
          {root ? t.commentReply : t.commentAdd}
        </button>
      </form>
      {!author && <p>{t.commentAuthorRequired}</p>}
    </fieldset>
  );
}

function Message({
  item,
  state,
  apply,
}: {
  item: XlsxThreads["items"][number];
  state: UiSnapshot;
  apply: (change: XlsxThreadEdit) => void;
}) {
  const t = messages(state.locale);
  const [text, setText] = useState(item.text);
  useEffect(() => setText(item.text), [item.text]);
  return (
    <article aria-label={`${t.commentItem}: ${item.author}`}>
      <p>
        {item.author} <time dateTime={item.date}>{item.date}</time>
      </p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          apply({ action: "update", id: item.id, text });
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
        <button type="submit" disabled={!text.trim() || text === item.text}>
          {t.commentUpdate}
        </button>
      </form>
      <button
        type="button"
        onClick={() => apply({ action: "delete", id: item.id })}
      >
        {item.parentId === null ? t.commentRemove : t.commentRemoveSingle}
      </button>
    </article>
  );
}
