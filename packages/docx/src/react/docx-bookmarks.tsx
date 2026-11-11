import { useState } from "react";
import type { DocxPosition, DocxSelection } from "../core/docx-hit.js";
import type { DocumentEditor, DocumentOverview } from "../web/editor.js";
import { checkDocxBookmark, type DocxBookmarkEdit } from "../web/foundation.js";
import type { EditorController } from "./context.js";
import type { Messages } from "@open-document/ui/messages-en";
import { Icon } from "@open-document/ui/icons";

export function bookmarkAtPosition(
  bookmarks: DocumentOverview["bookmarks"],
  focus: DocxPosition,
  order: ReadonlyMap<number, { index: number; story: number | null }>,
): string | undefined {
  const compare = (left: DocxPosition, right: DocxPosition): number | null => {
    if (left.paragraph === right.paragraph) return left.offset - right.offset;
    const a = order.get(left.paragraph);
    const b = order.get(right.paragraph);
    return a && b && a.story === b.story ? a.index - b.index : null;
  };
  let current: string | undefined;
  let selected: DocxSelection | undefined;
  for (const bookmark of bookmarks) {
    const range = bookmark.selection;
    if (!range || bookmark.reason) continue;
    const fromStart = compare(focus, range.anchor);
    const fromEnd = compare(focus, range.focus);
    if (fromStart === null || fromEnd === null) continue;
    const contains =
      (fromStart === 0 && fromEnd === 0) ||
      ((fromStart > 0 || (fromStart === 0 && focus.affinity === "after")) &&
        (fromEnd < 0 || (fromEnd === 0 && focus.affinity === "before")));
    if (!contains) continue;
    if (selected) {
      const startOrder = compare(range.anchor, selected.anchor);
      const endOrder = compare(range.focus, selected.focus);
      if (
        startOrder === null ||
        startOrder < 0 ||
        (startOrder === 0 && (endOrder === null || endOrder >= 0))
      )
        continue;
    }
    selected = range;
    current = bookmark.name;
  }
  return current;
}

export function DocxBookmarks({
  controller,
  editor,
  result,
  current,
  disabled,
  t,
}: {
  controller: EditorController;
  editor: DocumentEditor;
  result: DocumentOverview;
  current: string | undefined;
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
      return editor.review.editBookmark(change);
    });
  return (
    <section aria-label={t.bookmarks}>
      <h3>
        <Icon name="bookmark" />
        {t.bookmarks}
      </h3>
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
          <legend>
            <Icon name="bookmark" />
            {t.bookmarkCreate}
          </legend>
          <label>
            {t.bookmarkName}
            <input
              required
              maxLength={40}
              value={name}
              onChange={(event) => setName(event.currentTarget.value)}
            />
          </label>
          <button type="submit">
            <Icon name="plus" />
            {t.bookmarkCreate}
          </button>
        </fieldset>
      </form>
      <ul className="od-docx-reference-list od-docx-bookmarks">
        {result.bookmarks.map((b, i) => (
          <Bookmark
            key={`${i}:${b.name}`}
            bookmark={b}
            current={current === b.name && !b.reason}
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
  current,
  disabled,
  t,
  apply,
}: {
  bookmark: DocumentOverview["bookmarks"][number];
  current: boolean;
  disabled: boolean;
  t: Messages;
  apply: (change: DocxBookmarkEdit) => void;
}) {
  const [name, setName] = useState(b.name);
  return (
    <li aria-current={current ? "location" : undefined}>
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
          <button type="submit">
            <Icon name="pen" />
            {t.bookmarkRename}
          </button>
          <button
            type="button"
            onClick={() => apply({ action: "goTo", name: b.name })}
          >
            <Icon name="arrow-right" />
            {t.bookmarkGoTo}
          </button>
          <button
            type="button"
            onClick={() => apply({ action: "remove", name: b.name })}
          >
            <Icon name="trash" />
            {t.bookmarkRemove}
          </button>
        </fieldset>
        {b.reason && <p>{b.reason}</p>}
      </form>
    </li>
  );
}
