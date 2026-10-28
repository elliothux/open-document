import { PptxConnectors } from "./pptx-connectors.js";
import { PptxShapeOptions } from "./pptx-shape-options.js";
import { PptxDiagram } from "./pptx-diagram.js";
import { WordArt } from "@open-document/ui/word-art";
import { PptxMedia } from "./pptx-media.js";
import { useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { PptxObjectEdit, PptxHyperlink } from "../web/pptx.js";
import { pptxInsertKinds } from "../web/pptx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { PptxPaint } from "./pptx-paint.js";
import { PptxCharts } from "./pptx-chart.js";
import { PptxMath } from "./pptx-math.js";
import { PlaceholderType, PptxPlaceholder } from "./pptx-placeholder.js";
import type { PptxPlaceholderType } from "../web/pptx.js";
import { PptxShapeAdjustments } from "./pptx-shape-adjustments.js";
import { PptxTextFrame } from "./pptx-text-frame.js";
import { PptxPicture, ImageInsetsForm } from "./pptx-picture.js";
import { PptxFormat, PptxParagraph } from "./pptx-format.js";
import {
  PptxCells,
  PptxSplitCell,
  PptxTableSize,
  PptxTableStyle,
} from "./pptx-cells.js";

type Insert = Extract<PptxObjectEdit, { action: "insert" }>;

export function PptxObjects({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState<Insert>({
    action: "insert",
    kind: "text",
    x: 72,
    y: 72,
    width: 240,
    height: 96,
    text: "",
  });
  const query = editor.query;
  const [placeholderType, setPlaceholderType] =
    useState<PptxPlaceholderType>("body");
  const selectedRows = query.table
    ? query.table.lastRow - query.table.firstRow + 1
    : 0;
  const selectedColumns = query.table
    ? query.table.lastColumn - query.table.firstColumn + 1
    : 0;
  const [rows, setRows] = useState("2");
  const [columns, setColumns] = useState("2");
  const selected = query.objects.find(
    (object) => object.id === query.selection.object,
  );
  const objectMode = query.selection.mode === "object";
  const sameParent = query.objects
    .filter((object) => query.selection.objects.includes(object.id))
    .every((object) => object.parent === selected?.parent);
  const hyperlink = objectMode ? selected?.hyperlink : query.textHyperlink;
  const duplicationReason = query.objects.find(
    (object) =>
      query.selection.objects.includes(object.id) && object.duplicateReason,
  )?.duplicateReason;
  const deletionReason = query.objects.find(
    (object) =>
      query.selection.objects.includes(object.id) && object.deleteReason,
  )?.deleteReason;
  const shapeTypeReason = query.objects.find(
    (object) =>
      query.selection.objects.includes(object.id) && object.shapeTypeReason,
  )?.shapeTypeReason;
  return (
    <section aria-label={t.insertObject}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              ...draft,
              text: draft.kind === "line" ? "" : draft.text,
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !!query.readOnlyReason}>
          <legend>{t.insertObject}</legend>
          <label>
            {t.objectKind}
            <select
              value={draft.kind}
              onChange={(event) => {
                const kind = pptxInsertKinds.find(
                  (kind) => kind === event.currentTarget.value,
                );
                if (kind) setDraft({ ...draft, kind });
              }}
            >
              <PptxShapeOptions t={t} />
            </select>
          </label>
          {(
            [
              ["x", t.objectX],
              ["y", t.objectY],
              ["width", t.objectWidth],
              ["height", t.objectHeight],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                step="any"
                required
                value={draft[key]}
                min={
                  key === "x" || key === "y"
                    ? -14400
                    : draft.kind === "line"
                      ? 0
                      : 0.1
                }
                max={14400}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    [key]: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
          ))}
          <label>
            {t.objectText}
            <textarea
              value={draft.text}
              maxLength={32767}
              disabled={draft.kind === "line"}
              onChange={(event) =>
                setDraft({ ...draft, text: event.currentTarget.value })
              }
            />
          </label>
          <button type="submit">{t.insertObject}</button>
          <button
            type="button"
            disabled={
              !objectMode ||
              !query.selection.objects.length ||
              !!shapeTypeReason ||
              draft.kind === "text" ||
              draft.kind === "line"
            }
            title={shapeTypeReason}
            onClick={() =>
              controller.run(() =>
                draft.kind === "text" || draft.kind === "line"
                  ? Promise.resolve()
                  : editor.editObjects({
                      action: "shapeType",
                      preset: draft.kind,
                    }),
              )
            }
          >
            {t.changeShape}
          </button>
          {query.editView.kind !== "slide" && (
            <>
              <PlaceholderType
                value={placeholderType}
                onChange={setPlaceholderType}
                state={state}
              />
              <button
                type="button"
                disabled={!!query.editView.operations.rename}
                onClick={() =>
                  controller.run(() =>
                    editor.editObjects({
                      action: "insertPlaceholder",
                      type: placeholderType,
                      x: draft.x,
                      y: draft.y,
                      width: draft.width,
                      height: draft.height,
                      text: draft.text,
                    }),
                  )
                }
              >
                {t.pptxInsertPlaceholder}
              </button>
            </>
          )}
        </fieldset>
      </form>
      <WordArt
        controller={controller}
        state={state}
        disabled={disabled || !!editor.query.readOnlyReason}
        apply={async (preset, text) => {
          await editor.editObjects({ action: "insertWordArt", preset, text });
          editor.focus();
        }}
      />
      <PptxDiagram
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        box={{
          x: draft.x,
          y: draft.y,
          width: draft.width,
          height: draft.height,
        }}
      />
      <PptxPlaceholder
        key={`placeholder:${selected?.id}:${JSON.stringify(selected?.placeholder.value)}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "insertTable",
              rows: Number(rows),
              columns: Number(columns),
              x: draft.x,
              y: draft.y,
              width: draft.width,
              height: draft.height,
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !!query.readOnlyReason}>
          <legend>{t.insertTable}</legend>
          <label>
            {t.tableRows}
            <input
              type="number"
              min={1}
              max={1000}
              step={1}
              required
              value={rows}
              onChange={(event) => setRows(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.tableColumns}
            <input
              type="number"
              min={1}
              max={63}
              step={1}
              required
              value={columns}
              onChange={(event) => setColumns(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={
              !Number.isInteger(Number(rows)) ||
              !Number.isInteger(Number(columns)) ||
              Number(rows) * Number(columns) > 4096
            }
          >
            {t.insertTable}
          </button>
          {objectMode &&
            query.selection.objects.length === 1 &&
            selected?.placeholder.value &&
            ["tbl", "obj"].includes(selected.placeholder.value.type) && (
              <button
                type="button"
                disabled={
                  !!selected.tableFillReason ||
                  !Number.isInteger(Number(rows)) ||
                  !Number.isInteger(Number(columns)) ||
                  Number(rows) * Number(columns) > 4096
                }
                title={selected.tableFillReason}
                onClick={() =>
                  controller.run(() =>
                    editor.editObjects({
                      action: "fillTable",
                      rows: Number(rows),
                      columns: Number(columns),
                    }),
                  )
                }
              >
                {t.fillTablePlaceholder}
              </button>
            )}
        </fieldset>
      </form>
      {query.table && (
        <fieldset disabled={disabled || !!query.readOnlyReason}>
          <legend>{t.tableProperties}</legend>
          <p>
            {t.address}: {query.table.row + 1}, {query.table.column + 1} (
            {query.table.rows} × {query.table.columns})
            {(selectedRows > 1 || selectedColumns > 1) &&
              `: ${query.table.firstRow + 1}, ${query.table.firstColumn + 1} – ${query.table.lastRow + 1}, ${query.table.lastColumn + 1}`}
          </p>
          {(
            [
              ["insertRowBefore", t.rowBefore],
              ["insertRowAfter", t.rowAfter],
              ["deleteRow", t.deleteRow],
              [
                "insertColumnBefore",
                query.table.rtl ? t.columnAfter : t.columnBefore,
              ],
              [
                "insertColumnAfter",
                query.table.rtl ? t.columnBefore : t.columnAfter,
              ],
              ["deleteColumn", t.deleteColumn],
              ["merge", t.mergeCells],
              ["unmerge", t.unmerge],
            ] as const
          ).map(([operation, label]) => (
            <button
              key={operation}
              type="button"
              disabled={!!query.table!.operations[operation]}
              title={query.table!.operations[operation]}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() =>
                controller.run(() =>
                  editor.editObjects({ action: "tableStructure", operation }),
                )
              }
            >
              {label}
            </button>
          ))}
          {query.table.reason && <p>{query.table.reason}</p>}
          <PptxTableSize
            key={`${state.document?.documentId}:${JSON.stringify([query.selection, query.table.rowHeight, query.table.columnWidth])}`}
            controller={controller}
            state={state}
            editor={editor}
          />
          <PptxSplitCell
            key={`${query.table.object}:${query.table.row}:${query.table.column}`}
            controller={controller}
            state={state}
            editor={editor}
            disabled={disabled}
          />
        </fieldset>
      )}
      {query.table && (
        <PptxTableStyle
          key={`${state.document?.documentId}:${query.table.object}:${JSON.stringify(query.table.style)}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled || !!query.readOnlyReason}
        />
      )}
      {query.table && (
        <PptxCells
          key={JSON.stringify([
            query.selection.mode,
            query.table.firstRow,
            query.table.lastRow,
            query.table.firstColumn,
            query.table.lastColumn,
            query.table.format,
          ])}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
      )}
      <fieldset disabled={disabled || !!query.readOnlyReason}>
        <legend>{t.insertImage}</legend>
        <label>
          {t.pictureFile}
          <input
            type="file"
            accept=".png,.jpg,.jpeg,image/png,image/jpeg"
            onChange={(event) => {
              const file = event.currentTarget.files?.[0];
              event.currentTarget.value = "";
              if (!file) return;
              controller.run(async () => {
                if (!file.size || file.size > 4194304)
                  throw new Error(t.imageInputLimit);
                await editor.editObjects({
                  action: "insertImage",
                  bytes: new Uint8Array(await file.arrayBuffer()),
                  x: draft.x,
                  y: draft.y,
                  width: draft.width,
                  height: draft.height,
                });
              });
            }}
          />
        </label>
      </fieldset>
      <PptxMedia
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        box={{
          x: draft.x,
          y: draft.y,
          width: draft.width,
          height: draft.height,
        }}
      />
      <PptxPicture
        key={`${state.document?.documentId}:${JSON.stringify([query.selection, selected?.picture])}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled || !!query.readOnlyReason}
      />
      <ImageInsetsForm
        key={`image-insets:${state.document?.documentId}:${query.selection.objects.join(",")}`}
        controller={controller}
        state={state}
        values={selected?.imageInsets ?? [0, 0, 0, 0]}
        reason={
          query.objects.find(
            (object) =>
              query.selection.objects.includes(object.id) &&
              object.imageInsetsReason,
          )?.imageInsetsReason ?? ""
        }
        disabled={
          disabled || !objectMode || !selected || !!query.readOnlyReason
        }
        onApply={(insets) =>
          editor.editObjects({ action: "imageInsets", insets })
        }
      />
      <button
        type="button"
        disabled={
          disabled ||
          !objectMode ||
          !selected ||
          !sameParent ||
          !!duplicationReason
        }
        title={duplicationReason}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "duplicate", dx: 18, dy: 18 }),
          )
        }
      >
        {t.duplicateObject}
      </button>
      <button
        type="button"
        disabled={
          disabled ||
          query.selection.mode !== "object" ||
          !selected ||
          !sameParent ||
          !!deletionReason
        }
        title={deletionReason}
        onClick={() =>
          controller.run(() => editor.editObjects({ action: "delete" }))
        }
      >
        {t.deleteObject}
      </button>
      <button
        type="button"
        disabled={disabled || !!query.groupReason}
        title={query.groupReason}
        onClick={() =>
          controller.run(() => editor.editObjects({ action: "group" }))
        }
      >
        {t.groupObjects}
      </button>
      <button
        type="button"
        disabled={disabled || !!query.ungroupReason}
        title={query.ungroupReason}
        onClick={() =>
          controller.run(() => editor.editObjects({ action: "ungroup" }))
        }
      >
        {t.ungroupObjects}
      </button>
      {selected?.deleteReason && <p>{selected.deleteReason}</p>}
      {selected?.duplicateReason &&
        selected.duplicateReason !== selected.deleteReason && (
          <p>{selected.duplicateReason}</p>
        )}
      <PptxConnectors
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        insert
      />
      <PptxConnectors
        key={`connector:${selected?.id}:${JSON.stringify(selected?.connector)}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        insert={false}
      />
      <PptxShapeAdjustments
        key={`${state.document?.documentId}:${query.revision}:${query.selection.objects.join(",")}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxHyperlink
        key={`link:${state.document?.documentId}:${query.selection.object}:${JSON.stringify([hyperlink?.value ?? null, !objectMode && query.textHyperlink.mixed])}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxPaint
        key={`${state.document?.documentId}:${query.selection.mode}:${query.selection.objects.map((id) => JSON.stringify(query.objects.find((o) => o.id === id)?.appearance)).join(",")}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxCharts
        key={`chart:${query.revision}:${query.selection.object}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxMath
        key={`math:${query.revision}:${query.selection.object}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxFormat
        key={`${state.document?.documentId}:${query.selection.objects.join(",")}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxParagraph
        key={`paragraph:${state.document?.documentId}:${query.selection.objects.join(",")}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxTextFrame
        key={`${state.document?.documentId}:${JSON.stringify(query.objects.filter((object) => query.selection.objects.includes(object.id)).map((object) => [object.id, object.textFrame]))}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
    </section>
  );
}

function PptxHyperlink({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.query;
  const textMode = query.selection.mode === "text";
  const current = textMode
    ? query.textHyperlink
    : query.objects.find((object) => object.id === query.selection.object)
        ?.hyperlink;
  const link = current?.value;
  const [kind, setKind] = useState<PptxHyperlink["kind"]>(
    link?.kind ?? "external",
  );
  const [address, setAddress] = useState(
    link?.kind === "external" ? link.target : "",
  );
  const [slide, setSlide] = useState(
    link?.kind === "slide" ? link.target : (query.slides[0]?.id ?? ""),
  );
  const actions = [
    ["firstslide", t.hyperlinkFirstSlide],
    ["lastslide", t.hyperlinkLastSlide],
    ["nextslide", t.hyperlinkNextSlide],
    ["previousslide", t.hyperlinkPreviousSlide],
    ["lastslideviewed", t.hyperlinkLastViewed],
    ["endshow", t.hyperlinkEndShow],
  ] as const;
  const [action, setAction] = useState<
    Extract<PptxHyperlink, { kind: "action" }>["target"]
  >(link?.kind === "action" ? link.target : "nextslide");
  const blocked =
    disabled ||
    query.selection.objects.length !== 1 ||
    !current ||
    !!current.reason;
  return (
    <section aria-label={textMode ? t.textHyperlink : t.objectHyperlink}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "hyperlink",
              link:
                kind === "action"
                  ? { kind, target: action }
                  : { kind, target: kind === "external" ? address : slide },
            }),
          );
        }}
      >
        <fieldset disabled={blocked}>
          <legend>{textMode ? t.textHyperlink : t.objectHyperlink}</legend>
          <label>
            {t.hyperlinkKind}
            <select
              aria-label={t.hyperlinkKind}
              value={kind}
              onChange={(event) => {
                const kind = event.currentTarget.value;
                if (
                  kind === "external" ||
                  kind === "slide" ||
                  kind === "action"
                )
                  setKind(kind);
              }}
            >
              <option value="external">{t.hyperlinkExternal}</option>
              <option value="slide">{t.hyperlinkSlide}</option>
              <option value="action">{t.hyperlinkAction}</option>
            </select>
          </label>
          {kind === "external" ? (
            <label>
              {t.hyperlinkAddress}
              <input
                type="url"
                required
                maxLength={2048}
                value={address}
                onChange={(event) => setAddress(event.currentTarget.value)}
              />
            </label>
          ) : kind === "action" ? (
            <label>
              {t.hyperlinkNavigation}
              <select
                aria-label={t.hyperlinkNavigation}
                value={action}
                onChange={(event) => {
                  const choice = actions.find(
                    ([value]) => value === event.currentTarget.value,
                  );
                  if (choice) setAction(choice[0]);
                }}
              >
                {actions.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
          ) : (
            <label>
              {t.hyperlinkTargetSlide}
              <select
                aria-label={t.hyperlinkTargetSlide}
                value={slide}
                onChange={(event) => setSlide(event.currentTarget.value)}
              >
                {query.slides.map((slide, index) => (
                  <option key={slide.id} value={slide.id}>
                    {index + 1}. {slide.title}
                  </option>
                ))}
              </select>
            </label>
          )}
          <button type="submit">{t.hyperlinkApply}</button>
          <button
            type="button"
            disabled={!link && !(textMode && query.textHyperlink.mixed)}
            onClick={() =>
              controller.run(() =>
                editor.editObjects({ action: "hyperlink", link: null }),
              )
            }
          >
            {t.hyperlinkRemove}
          </button>
        </fieldset>
      </form>
      {current?.reason && <p>{current.reason}</p>}
      {!blocked &&
        link &&
        (link.kind === "external" ? (
          <a href={link.target} target="_blank" rel="noopener noreferrer">
            {t.hyperlinkOpen}
          </a>
        ) : link.kind === "action" &&
          (link.target === "lastslideviewed" || link.target === "endshow") ? (
          <p>{t.hyperlinkShowOnly}</p>
        ) : (
          <button
            type="button"
            onClick={() => controller.run(() => editor.followHyperlink())}
          >
            {t.hyperlinkOpen}
          </button>
        ))}
    </section>
  );
}
