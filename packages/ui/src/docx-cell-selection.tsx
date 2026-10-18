import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxFormatting } from "@open-document/web/foundation";
import type {
  DocxCellMargins,
  DocxCellBorders,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxMargins } from "./docx-margins.js";
import { DocxBorders } from "./docx-borders.js";

export function DocxCellSelection({
  controller,
  state,
  editor,
  selected,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  selected: NonNullable<DocxFormatting["cellSelection"]["value"]>;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [fill, setFill] = useState(
    `#${selected.fill.kind === "value" ? (selected.fill.value ?? "ffffff") : "ffffff"}`,
  );
  const margins: Partial<DocxCellMargins> = {};
  const borders: DocxCellBorders = {
    top: null,
    right: null,
    bottom: null,
    left: null,
  };
  for (const side of ["top", "right", "bottom", "left"] as const) {
    const value = selected.margins[side];
    if (value.kind === "value") margins[side] = value.value;
    const border = selected.borders[side];
    if (border.kind === "value") borders[side] = border.value;
  }
  return (
    <section aria-label={t.selectedCells}>
      <h3>
        {t.selectedCells}: {selected.count}
      </h3>
      <p>{t.cellSelectionText}</p>
      <fieldset disabled={disabled}>
        <legend>{t.cellFill}</legend>
        {selected.fill.kind === "mixed" && <p>{t.mixed}</p>}
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editTable({ action: "cellFill", value: fill.slice(1) }),
            );
          }}
        >
          <label>
            {t.cellFill}
            <input
              type="color"
              value={fill}
              onChange={(event) => setFill(event.currentTarget.value)}
            />
          </label>
          <button type="submit" aria-label={`${t.apply} ${t.cellFill}`}>
            {t.apply}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editTable({ action: "cellFill", value: null }),
              )
            }
          >
            {t.clearCellFill}
          </button>
        </form>
      </fieldset>
      <fieldset disabled={disabled}>
        <legend>{t.cellVerticalAlign}</legend>
        {selected.verticalAlign.kind === "mixed" && <p>{t.mixed}</p>}
        {(
          [
            ["top", t.alignTop],
            ["center", t.alignMiddle],
            ["bottom", t.alignBottom],
          ] as const
        ).map(([value, label]) => (
          <button
            type="button"
            key={value}
            aria-pressed={
              selected.verticalAlign.kind === "value" &&
              selected.verticalAlign.value === value
            }
            onClick={() =>
              controller.run(() =>
                editor.editTable({ action: "cellVerticalAlign", value }),
              )
            }
          >
            {label}
          </button>
        ))}
        <button
          type="button"
          onClick={() =>
            controller.run(() =>
              editor.editTable({ action: "cellVerticalAlign", value: null }),
            )
          }
        >
          {t.inheritStyleProperty}
        </button>
      </fieldset>
      <DocxMargins
        controller={controller}
        state={state}
        editor={editor}
        action="cellMargins"
        value={margins}
        label={t.cellMargins}
        disabled={disabled}
      />
      <DocxBorders
        controller={controller}
        state={state}
        editor={editor}
        cell={borders}
        disabled={disabled}
      />
      <label>
        <input
          type="checkbox"
          disabled={disabled}
          checked={
            selected.rowSplit.kind === "value" && selected.rowSplit.value
          }
          ref={(input) => {
            if (input) input.indeterminate = selected.rowSplit.kind === "mixed";
          }}
          onChange={(event) => {
            const value = event.currentTarget.checked;
            controller.run(() =>
              editor.editTable({ action: "rowSplit", value }),
            );
          }}
        />
        {t.tableRowSplit}
      </label>
      <DocxRowHeight
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
        height={
          selected.rowHeight.kind === "value" ? selected.rowHeight.value : null
        }
        rule={
          selected.rowHeightRule.kind === "value"
            ? selected.rowHeightRule.value
            : null
        }
        maxHeight={selected.maxRowHeight}
      />
    </section>
  );
}

export function DocxRowHeight({
  controller,
  state,
  editor,
  disabled,
  height,
  rule,
  maxHeight,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  height: number | null;
  rule: "atLeast" | "exact" | null;
  maxHeight: number;
}) {
  const t = messages(state.locale);
  const [value, setValue] = useState(height === null ? "" : String(height));
  const [mode, setMode] = useState<"atLeast" | "exact" | "">(rule ?? "");
  const label =
    mode === "exact"
      ? t.rowHeightExactValue
      : mode === "atLeast"
        ? t.rowHeightMinimum
        : t.tableRowHeight;
  const valid =
    value !== "" &&
    mode !== "" &&
    Number.isFinite(Number(value)) &&
    Number(value) >= 0 &&
    Number(value) <= maxHeight &&
    Number.isInteger(Number(value) * 20);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (valid)
          controller.run(() =>
            editor.editTable({
              action: "rowHeight",
              value: Number(value),
              rule: mode,
            }),
          );
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.tableRowHeight}</legend>
        <label>
          {t.rowHeightRule}
          <select
            aria-label={t.rowHeightRule}
            value={mode}
            required
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "atLeast" || value === "exact") setMode(value);
            }}
          >
            {rule === null && (
              <option value="" disabled>
                {t.mixed}
              </option>
            )}
            <option value="atLeast">{t.rowHeightAtLeast}</option>
            <option value="exact">{t.rowHeightExact}</option>
          </select>
        </label>
        <label>
          {label}
          <input
            type="number"
            min={0}
            max={maxHeight}
            step={0.05}
            required
            value={value}
            placeholder={height === null ? t.mixed : undefined}
            onChange={(event) => setValue(event.currentTarget.value)}
          />
        </label>
        <button
          type="submit"
          aria-label={`${t.apply} ${label}`}
          disabled={!valid}
        >
          {t.apply}
        </button>
      </fieldset>
    </form>
  );
}
