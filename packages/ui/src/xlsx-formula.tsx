import { useRef } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { NativeSlot } from "./controls.js";
import { messages } from "./messages.js";

export function XlsxStatistics({
  state,
  editor,
}: {
  state: UiSnapshot;
  editor: SpreadsheetEditor;
}) {
  const t = messages(state.locale),
    statistics = editor.currentState.statistics;
  const rows: [string, number | null][] = [
    [t.statisticsCount, statistics.count],
    [t.statisticsNumbers, statistics.countNumbers],
    [t.statisticsSum, statistics.sum],
    [t.statisticsAverage, statistics.average],
    [t.statisticsMin, statistics.min],
    [t.statisticsMax, statistics.max],
  ];
  return (
    <span
      role="group"
      aria-label={t.selectionStatistics}
      title={statistics.reason || undefined}
    >
      {rows.map(([label, value]) => (
        <span key={label} aria-label={label}>
          {label}: {value ?? "—"}{" "}
        </span>
      ))}
      {statistics.reason && <span>{statistics.reason}</span>}
    </span>
  );
}

export function XlsxFormula({
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
    field = useRef<HTMLInputElement>(null),
    selection = editor.currentState.selection,
    calculationReason = editor.currentState.cells[0]?.calculationReason;
  return (
    <div className="od-formula">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const range = field.current?.value.trim() ?? "";
          controller.run(() => editor.select(range));
        }}
      >
        <input
          key={`${selection.sheet}:${selection.address}`}
          ref={field}
          aria-label={t.cellRange}
          defaultValue={selection.address}
          maxLength={32}
          required
          disabled={disabled}
        />
        <button type="submit" disabled={disabled}>
          {t.goToRange}
        </button>
      </form>
      <label>
        <span>{t.formulaInput}</span>
        <NativeSlot node={editor.formulaBar} />
      </label>
      {calculationReason && <span role="status">{calculationReason}</span>}
      <label
        onMouseDown={(event) => {
          if (event.button === 0) event.preventDefault();
        }}
      >
        <input
          key={state.document?.documentId}
          type="checkbox"
          disabled={disabled}
          defaultChecked={editor.acceptValidationWarnings}
          onChange={(event) => {
            editor.acceptValidationWarnings = event.currentTarget.checked;
          }}
        />
        {t.acceptValidationWarnings}
      </label>
    </div>
  );
}
