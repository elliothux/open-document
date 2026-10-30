import { useRef, useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { NativeSlot } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";

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
  const documentId = state.document?.documentId;
  const [draft, setDraft] = useState<{
    documentId: typeof documentId;
    value: string;
  }>();
  const snapshot = editor.getSnapshot();
  // A protected cell still permits navigation to another cell.
  const navigationDisabled =
    state.loading ||
    snapshot.paused ||
    snapshot.closed ||
    snapshot.composition ||
    snapshot.dragging ||
    !!snapshot.busy ||
    snapshot.stopped;
  return (
    <div className="od-formula">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const range = field.current?.value.trim() ?? "";
          const submitted = draft;
          controller.run(async () => {
            await editor.select(range);
            setDraft((current) =>
              current === submitted ? undefined : current,
            );
          });
        }}
      >
        <input
          key={documentId}
          ref={field}
          aria-label={t.cellRange}
          value={
            draft && draft.documentId === documentId
              ? draft.value
              : selection.address
          }
          onChange={(event) =>
            setDraft({ documentId, value: event.currentTarget.value })
          }
          onFocus={(event) =>
            setDraft({ documentId, value: event.currentTarget.value })
          }
          maxLength={32}
          required
          disabled={navigationDisabled}
        />
        <button type="submit" disabled={navigationDisabled}>
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
