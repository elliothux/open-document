import { useEffect, useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  xlsxNumberFormats,
  checkXlsxHyperlinkTarget,
  type XlsxCellFormat,
  type XlsxCellBorder,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { XlsxFormatPainter } from "./xlsx-format-painter.js";
import { XlsxValidation } from "./xlsx-validation.js";
import { XlsxConditional } from "./xlsx-conditional.js";

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
  function set<K extends keyof XlsxCellFormat>(
    key: K,
    value: XlsxCellFormat[K],
  ) {
    setPatch((old) => {
      const next = { ...old };
      if (value === undefined) delete next[key];
      else next[key] = value;
      return next;
    });
  }
  const families = Object.keys(controller.options.resources.profile).filter(
    (key) => !key.includes("|"),
  );
  const options = (values: readonly string[]) => (
    <>
      <option value="">{t.keepStyleProperty}</option>
      {values.map((value) => (
        <option key={value} value={value}>
          {value}
        </option>
      ))}
    </>
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
        {merging.discarded > 0 && (
          <label>
            <input
              type="checkbox"
              checked={discard}
              onChange={(event) => setDiscard(event.currentTarget.checked)}
            />
            {t.discardMergedValues}
          </label>
        )}
        <button
          type="button"
          disabled={
            !!merging.mergeReason || (merging.discarded > 0 && !discard)
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
          <label>
            {t.fontFamily}
            <select
              value={patch.family ?? ""}
              onChange={(event) =>
                set("family", event.currentTarget.value || undefined)
              }
            >
              {options(families)}
            </select>
          </label>
          <label>
            {t.fontSize}
            <input
              type="number"
              min={1}
              max={409}
              step="any"
              value={patch.size ?? ""}
              placeholder={
                current.size === null ? t.mixed : String(current.size)
              }
              onChange={(event) =>
                set(
                  "size",
                  event.currentTarget.value === ""
                    ? undefined
                    : Number(event.currentTarget.value),
                )
              }
            />
          </label>
          {(["bold", "italic", "wrap"] as const).map((key) => (
            <label key={key}>
              {t[key]}
              <select
                value={patch[key] === undefined ? "" : String(patch[key])}
                onChange={(event) =>
                  set(
                    key,
                    event.currentTarget.value === ""
                      ? undefined
                      : event.currentTarget.value === "true",
                  )
                }
              >
                <option value="">
                  {current[key] === null ? t.mixed : t.keepStyleProperty}
                </option>
                <option value="true">{t.styleOn}</option>
                <option value="false">{t.styleOff}</option>
              </select>
            </label>
          ))}
          <label>
            {t.textColor}
            <input
              value={patch.color ?? ""}
              pattern="[0-9A-Fa-f]{6}"
              placeholder={current.color ?? t.mixed}
              onChange={(event) =>
                set("color", event.currentTarget.value || undefined)
              }
            />
          </label>
          <label>
            {t.cellFill}
            <input
              value={patch.fill ?? ""}
              pattern="[0-9A-Fa-f]{6}"
              placeholder={current.fill ?? t.mixed}
              onChange={(event) =>
                set("fill", event.currentTarget.value || undefined)
              }
            />
          </label>
          <label>
            <input
              type="checkbox"
              checked={patch.fill === ""}
              onChange={(event) =>
                set("fill", event.currentTarget.checked ? "" : undefined)
              }
            />
            {t.noCellFill}
          </label>
          <label>
            {t.cellHorizontal}
            <select
              value={patch.horizontal ?? ""}
              onChange={(event) =>
                set(
                  "horizontal",
                  event.currentTarget.value === ""
                    ? undefined
                    : (event.currentTarget
                        .value as XlsxCellFormat["horizontal"]),
                )
              }
            >
              {options(["general", "left", "center", "right"])}
            </select>
          </label>
          <label>
            {t.cellVertical}
            <select
              value={patch.vertical ?? ""}
              onChange={(event) =>
                set(
                  "vertical",
                  event.currentTarget.value === ""
                    ? undefined
                    : (event.currentTarget.value as XlsxCellFormat["vertical"]),
                )
              }
            >
              {options(["top", "center", "bottom"])}
            </select>
          </label>
          <label>
            {t.cellNumberFormat}
            <select
              value={patch.numberFormat ?? ""}
              onChange={(event) =>
                set("numberFormat", event.currentTarget.value || undefined)
              }
            >
              {options(xlsxNumberFormats)}
            </select>
          </label>
          {(["left", "right", "top", "bottom"] as const).map((side) => (
            <fieldset key={side}>
              <legend>{t[`${side}CellBorder`]}</legend>
              <label>
                {t.cellBorderStyle}
                <select
                  value={patch[side]?.style ?? ""}
                  onChange={(event) =>
                    set(
                      side,
                      event.currentTarget.value === ""
                        ? undefined
                        : {
                            style: event.currentTarget
                              .value as XlsxCellBorder["style"],
                            color:
                              patch[side]?.color ??
                              current[side]?.color ??
                              "000000",
                          },
                    )
                  }
                >
                  {options(["none", "thin", "medium", "thick"])}
                </select>
              </label>
              <label>
                {t.textColor}
                <input
                  disabled={!patch[side]}
                  value={patch[side]?.color ?? "000000"}
                  required
                  pattern="[0-9A-Fa-f]{6}"
                  onChange={(event) =>
                    set(side, {
                      style: patch[side]?.style ?? "thin",
                      color: event.currentTarget.value,
                    })
                  }
                />
              </label>
            </fieldset>
          ))}
          <button type="submit" disabled={Object.keys(patch).length === 0}>
            {t.applyCellFormat}
          </button>
        </fieldset>
      </form>
      {current.readOnlyReason && <p>{current.readOnlyReason}</p>}
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
