import { useEffect, useLayoutEffect, useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  checkXlsxHyperlinkTarget,
  checkXlsxSheetEdit,
  type XlsxCellFormat,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { XlsxFormatPainter } from "./xlsx-format-painter.js";
import { XlsxValidation } from "./xlsx-validation.js";
import { XlsxFormatFields } from "./xlsx-format-fields.js";
import { XlsxConditional } from "./xlsx-conditional.js";
import { XlsxClipboard } from "./xlsx-clipboard.js";
import { XlsxProtection } from "./xlsx-protection.js";

type Props = {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
};

export function XlsxFormat({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale),
    current = editor.currentState.formatting;
  const [patch, setPatch] = useState<XlsxCellFormat>({});
  const [discard, setDiscard] = useState(false);
  const merging = editor.currentState.merging;
  useEffect(
    () => setDiscard(false),
    [editor, merging.range, state.document?.revision],
  );
  useEffect(() => setPatch({}), [editor]);
  const families = Object.keys(controller.options.resources.profile).filter(
    (key) => !key.includes("|"),
  );
  return (
    <section
      aria-label={t.cellFormat}
      onMouseDown={(event) => {
        if (
          event.target instanceof Element &&
          event.target.closest("button") &&
          event.button === 0
        )
          event.preventDefault();
      }}
    >
      <h3>{t.cellFormat}</h3>
      <XlsxClipboard
        key={state.document?.documentId}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <XlsxNote
        key={`${state.document?.documentId}:${editor.currentState.sheet}:${editor.currentState.note.address}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <XlsxHyperlink
        key={state.document?.documentId}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <XlsxConditional
        key={JSON.stringify([
          state.document?.documentId,
          editor.currentState.sheet,
          editor.currentState.selection.address,
          editor.currentState.conditionalFormats,
        ])}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <XlsxFormatPainter
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <fieldset disabled={disabled}>
        <legend>{t.mergeCells}</legend>
        <p>{merging.range}</p>
        {(merging.discarded > 0 || merging.discardedNotes > 0) && (
          <label>
            <input
              type="checkbox"
              checked={discard}
              onChange={(event) => setDiscard(event.currentTarget.checked)}
            />
            {merging.discardedNotes > 0
              ? t.discardMergedNotes
              : t.discardMergedValues}
          </label>
        )}
        <button
          type="button"
          disabled={
            !!merging.mergeReason ||
            ((merging.discarded > 0 || merging.discardedNotes > 0) && !discard)
          }
          onClick={() =>
            controller.run(() =>
              editor.editSheet({
                action: "merge",
                range: merging.range,
                discard,
              }),
            )
          }
        >
          {t.mergeCells}
        </button>
        <button
          type="button"
          disabled={!merging.merged || !!merging.unmergeReason}
          onClick={() =>
            controller.run(() =>
              editor.editSheet({ action: "unmerge", range: merging.range }),
            )
          }
        >
          {t.unmerge}
        </button>
        {(merging.mergeReason || merging.unmergeReason) && (
          <p>{merging.mergeReason || merging.unmergeReason}</p>
        )}
      </fieldset>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            await editor.formatCells(patch);
            setPatch({});
          });
        }}
      >
        <fieldset disabled={disabled || !!current.readOnlyReason}>
          <XlsxFormatFields
            format={patch}
            onChange={setPatch}
            current={current}
            families={families}
            state={state}
          />
          <button type="submit" disabled={Object.keys(patch).length === 0}>
            {t.applyCellFormat}
          </button>
        </fieldset>
      </form>
      {current.readOnlyReason && <p>{current.readOnlyReason}</p>}
      <XlsxProtection
        key={`protection:${state.document?.documentId}:${editor.currentState.sheet}:${editor.currentState.protection.protected}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <XlsxProtection
        key={`workbook-protection:${state.document?.documentId}:${editor.currentState.workbookProtection.protected}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        workbook
      />
      <XlsxValidation
        key={`${state.document?.documentId}:${editor.currentState.sheet}:${editor.currentState.selection.address}:${JSON.stringify(editor.currentState.dataValidation)}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
    </section>
  );
}

function XlsxNote({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale),
    query = editor.currentState,
    note = query.note;
  const [text, setText] = useState(note.text);
  useLayoutEffect(() => setText(note.text), [note.text]);
  const author = note.exists
    ? note.author
    : controller.options.commentAuthor?.name;
  return (
    <form
      aria-label={t.cellNote}
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() => {
          const change = {
            action: "note",
            cell: note.address,
            text,
            ...(author ? { author } : {}),
          } as const;
          checkXlsxSheetEdit(change);
          return editor.editSheet(change, query.sheet);
        });
      }}
    >
      <fieldset disabled={disabled || !!note.reason}>
        <legend>{t.cellNote}</legend>
        {note.author && <p>{note.author}</p>}
        <label>
          {t.cellNote}
          <textarea
            aria-label={t.cellNote}
            maxLength={32767}
            value={text}
            onChange={(event) => setText(event.currentTarget.value)}
          />
        </label>
        <button
          type="submit"
          disabled={
            (!note.exists && !author) ||
            !text.trim() ||
            (note.exists && text === note.text)
          }
        >
          {t.noteApply}
        </button>
        <button
          type="button"
          disabled={!note.exists}
          onClick={() =>
            controller.run(() =>
              editor.editSheet(
                { action: "note", cell: note.address, text: null },
                query.sheet,
              ),
            )
          }
        >
          {t.noteRemove}
        </button>
      </fieldset>
      {note.reason && <p>{note.reason}</p>}
      {!note.exists && !author && <p>{t.noteAuthorRequired}</p>}
    </form>
  );
}

function XlsxHyperlink({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale),
    query = editor.currentState,
    link = query.hyperlink;
  const [address, setAddress] = useState(link.target ?? "");
  useEffect(
    () => setAddress(link.target ?? ""),
    [editor, link.target, link.mixed],
  );
  disabled ||= !!link.readOnlyReason;
  return (
    <section aria-label={t.cellHyperlink}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => {
            checkXlsxHyperlinkTarget(address);
            return editor.editSheet({
              action: "hyperlink",
              range: query.selection.address,
              target: address,
            });
          });
        }}
      >
        <fieldset disabled={disabled}>
          <legend>{t.cellHyperlink}</legend>
          <label>
            {t.hyperlinkAddress}
            <input
              type="text"
              inputMode="url"
              required
              maxLength={2048}
              value={address}
              onChange={(event) => setAddress(event.currentTarget.value)}
            />
          </label>
          <p>{t.hyperlinkRange}</p>
          {link.mixed && <p>{t.mixed}</p>}
          <button type="submit">{t.hyperlinkApply}</button>
          <button
            type="button"
            disabled={!link.target && !link.mixed}
            onClick={() =>
              controller.run(() =>
                editor.editSheet({
                  action: "hyperlink",
                  range: query.selection.address,
                  target: null,
                }),
              )
            }
          >
            {t.hyperlinkRemove}
          </button>
        </fieldset>
      </form>
      {link.readOnlyReason && <p>{link.readOnlyReason}</p>}
      {link.navigationReason && <p>{link.navigationReason}</p>}
      {link.target &&
        !link.mixed &&
        (link.target.startsWith("#") ? (
          <button
            type="button"
            disabled={disabled || !!link.navigationReason}
            onClick={() =>
              controller.run(() =>
                editor.editSheet({
                  action: "openHyperlink",
                  range: query.selection.address,
                  sourceRevision: query.revision,
                }),
              )
            }
          >
            {t.hyperlinkOpen}
          </button>
        ) : (
          !disabled && (
            <a href={link.target} target="_blank" rel="noopener noreferrer">
              {t.hyperlinkOpen}
            </a>
          )
        ))}
    </section>
  );
}
