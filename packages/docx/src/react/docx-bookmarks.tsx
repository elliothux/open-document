import { useState } from "react";
import type { DocumentEditor, DocumentOverview } from "../web/editor.js";
import { checkDocxBookmark, type DocxBookmarkEdit } from "../web/foundation.js";
import type { EditorController } from "./context.js";
import type { Messages } from "@open-document/ui/messages-en";

export function DocxBookmarks({
  controller,
  editor,
  result,
  disabled,
  t,
}: {
  controller: EditorController;
  editor: DocumentEditor;
  result: DocumentOverview;
  disabled: boolean;
  t: Messages;
}) {
  const [name, setName] = useState("");
  const apply = (change: DocxBookmarkEdit) =>
    controller.run(() => {
      checkDocxBookmark(change);
      const next =
        change.action === "create"
          ? change.name
          : change.action === "rename"
            ? change.replacement
            : undefined;
      if (
        next &&
        result.bookmarks.some(
          (b) =>
            b.name.toLowerCase() === next.toLowerCase() &&
            (change.action !== "rename" || b.name !== change.name),
        )
      )
        throw new Error("Bookmark name already exists");
      return editor.editBookmark(change);
    });
  return (
    <section aria-label={t.bookmarks}>
      <h3>{t.bookmarks}</h3>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const selection = editor.getSnapshot().data.selection;
          if (selection) apply({ action: "create", name, selection });
        }}
      >
        <fieldset
          disabled={
            disabled ||
            !editor.getSnapshot().data.selection ||
            !!editor.getSnapshot().data.formatting?.cellSelection.value
          }
        >
          <legend>{t.bookmarkCreate}</legend>
          <label>
            {t.bookmarkName}
            <input
              required
              maxLength={40}
              value={name}
              onChange={(event) => setName(event.currentTarget.value)}
            />
          </label>
          <button type="submit">{t.bookmarkCreate}</button>
        </fieldset>
      </form>
      <ul>
        {result.bookmarks.map((b, i) => (
          <Bookmark
            key={`${i}:${b.name}`}
            bookmark={b}
            t={t}
            disabled={disabled}
            apply={apply}
          />
        ))}
      </ul>
    </section>
  );
}

function Bookmark({
  bookmark: b,
  disabled,
  t,
  apply,
}: {
  bookmark: DocumentOverview["bookmarks"][number];
  disabled: boolean;
  t: Messages;
  apply: (change: DocxBookmarkEdit) => void;
}) {
  const [name, setName] = useState(b.name);
  return (
    <li>
      <form
        aria-label={b.name}
        onSubmit={(event) => {
          event.preventDefault();
          apply({ action: "rename", name: b.name, replacement: name });
        }}
      >
        <fieldset disabled={disabled || !!b.reason}>
          <legend>{b.name}</legend>
          <label>
            {t.bookmarkName}
            <input
              required
              maxLength={40}
              value={name}
              onChange={(event) => setName(event.currentTarget.value)}
            />
          </label>
          <button type="submit">{t.bookmarkRename}</button>
          <button
            type="button"
            onClick={() => apply({ action: "goTo", name: b.name })}
          >
            {t.bookmarkGoTo}
          </button>
          <button
            type="button"
            onClick={() => apply({ action: "remove", name: b.name })}
          >
            {t.bookmarkRemove}
          </button>
        </fieldset>
        {b.reason && <p>{b.reason}</p>}
      </form>
    </li>
  );
}
