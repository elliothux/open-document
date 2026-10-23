import { ChartFields, initialChart } from "./chart-fields.js";
import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxChart } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxCharts({
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
  const selected =
    query.selection.objects.length === 1
      ? query.objects.find((object) => object.id === query.selection.object)
      : undefined;
  const chart = selected?.chart;
  const fill = !chart && selected?.chartFillReason === "";
  const [draft, setDraft] = useState<PptxChart>(chart ?? initialChart);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editObjects(
            chart
              ? { action: "chartData", ...draft }
              : fill
                ? { action: "fillChart", ...draft }
                : {
                    action: "insertChart",
                    ...draft,
                    x: 72,
                    y: 72,
                    width: 480,
                    height: 300,
                  },
          ),
        );
      }}
    >
      <fieldset
        disabled={
          disabled ||
          !!query.readOnlyReason ||
          (!!chart && !!selected?.chartDataReason)
        }
      >
        <legend>{t.chart}</legend>
        <ChartFields draft={draft} setDraft={setDraft} t={t} />
        <button type="submit" disabled={!draft.data}>
          {chart ? t.chartApply : fill ? t.chartFill : t.chartInsert}
        </button>
        {chart && selected?.chartDataReason && (
          <p>{selected.chartDataReason}</p>
        )}
      </fieldset>
    </form>
  );
}
