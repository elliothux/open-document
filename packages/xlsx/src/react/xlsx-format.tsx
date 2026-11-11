import { useEffect, useLayoutEffect, useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import {
  checkXlsxHyperlinkTarget,
  checkXlsxSheetEdit,
  type XlsxCellFormat,
} from "../web/xlsx.js";
import {
  preserveGridDraft,
  type EditorController,
  type UiSnapshot,
} from "./context.js";
import { messages } from "@open-document/ui/messages";
import { xlsxNoteTextUnits } from "@open-document/wasm/engine-source";
import { XlsxFormatPainter } from "./xlsx-format-painter.js";
import { XlsxValidation } from "./xlsx-validation.js";
import { XlsxFormatFields } from "./xlsx-format-fields.js";
import { XlsxConditional } from "./xlsx-conditional.js";
import { XlsxClipboard } from "./xlsx-clipboard.js";
import { XlsxProtection } from "./xlsx-protection.js";
import { XlsxSparkline } from "./xlsx-sparkline.js";
import { XlsxPictures } from "./xlsx-pictures.js";
import { XlsxShapes } from "./xlsx-shapes.js";
import { XlsxCharts } from "./xlsx-charts.js";
import { XlsxComments } from "./xlsx-comments.js";
import { Icon } from "@open-document/ui/icons";

type Props = {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
};

export function XlsxFormat({
  controller,
  state,
  editor,
  disabled,
  section = "format",
}: Props & { section?: "format" | "objects" | "review" | "validation" }) {
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
  if (section === "objects")
    return (
      <section aria-label={t.objects} onMouseDown={preserveGridDraft}>
        <XlsxPictures
          key={`pictures:${state.document?.documentId}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
        <XlsxShapes
          key={`shapes:${state.document?.documentId}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
        <XlsxCharts
          key={`charts:${state.document?.documentId}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
        <XlsxHyperlink
          key={`hyperlink:${state.document?.documentId}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
        <XlsxSparkline
          key={JSON.stringify([
            state.document?.documentId,
            editor.currentState.sheet,
            editor.currentState.selection.address,
            editor.currentState.sparklines,
          ])}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
      </section>
    );
  if (section === "review")
    return (
      <section aria-label={t.reviewTab} onMouseDown={preserveGridDraft}>
        <XlsxComments
          key={`comments:${state.document?.documentId}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
        <XlsxNote
          key={`note:${state.document?.documentId}:${editor.currentState.sheet}:${editor.currentState.note.address}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
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
      </section>
    );
  if (section === "validation")
    return (
      <XlsxValidation
        key={`validation:${state.document?.documentId}:${editor.currentState.sheet}:${editor.currentState.selection.address}:${JSON.stringify(editor.currentState.dataValidation)}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
    );
  return (
    <section aria-label={t.cellFormat} onMouseDown={preserveGridDraft}>
      <XlsxClipboard
        key={`clipboard:${state.document?.documentId}`}
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
        <legend>
          <Icon name="grid" />
          {t.mergeCells}
        </legend>
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
              editor.objects.editSheet({
                action: "merge",
                range: merging.range,
                discard,
              }),
            )
          }
        >
          <Icon name="table-cells" />
          {t.mergeCells}
        </button>
        <button
          type="button"
          disabled={!merging.merged || !!merging.unmergeReason}
          onClick={() =>
            controller.run(() =>
              editor.objects.editSheet({
                action: "unmerge",
                range: merging.range,
              }),
            )
          }
        >
          <Icon name="table-cells" />
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
            <Icon name="check" />
            {t.applyCellFormat}
          </button>
        </fieldset>
      </form>
      {current.readOnlyReason && <p>{current.readOnlyReason}</p>}
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
          return editor.objects.editSheet(change, query.sheet);
        });
      }}
    >
      <fieldset disabled={disabled || !!note.reason}>
        <legend>
          <Icon name="note" />
          {t.cellNote}
        </legend>
        {note.author && <p>{note.author}</p>}
        <label>
          {t.cellNote}
          <textarea
            aria-label={t.cellNote}
            maxLength={xlsxNoteTextUnits}
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
          <Icon name="check" />
          {t.noteApply}
        </button>
        <button
          type="button"
          disabled={!note.exists}
          onClick={() =>
            controller.run(() =>
              editor.objects.editSheet(
                { action: "note", cell: note.address, text: null },
                query.sheet,
              ),
            )
          }
        >
          <Icon name="trash" />
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
  return (
    <section aria-label={t.cellHyperlink}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => {
            checkXlsxHyperlinkTarget(address);
            return editor.objects.editSheet({
              action: "hyperlink",
              range: query.selection.address,
              target: address,
            });
          });
        }}
      >
        <fieldset disabled={disabled || !!link.readOnlyReason}>
          <legend>
            <Icon name="link" />
            {t.cellHyperlink}
          </legend>
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
          <button type="submit">
            <Icon name="check" />
            {t.hyperlinkApply}
          </button>
          <button
            type="button"
            disabled={!link.target && !link.mixed}
            onClick={() =>
              controller.run(() =>
                editor.objects.editSheet({
                  action: "hyperlink",
                  range: query.selection.address,
                  target: null,
                }),
              )
            }
          >
            <Icon name="trash" />
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
                editor.objects.editSheet({
                  action: "openHyperlink",
                  range: query.selection.address,
                  sourceRevision: query.revision,
                }),
              )
            }
          >
            <Icon name="arrow-right" />
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
