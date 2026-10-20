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
  const [draft, setDraft] = useState<PptxChart>(
    chart ?? {
      kind: "column",
      title: "Chart",
      data: "Category\tSeries 1\tSeries 2\nA\t10\t20\nB\t15\t5",
    },
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editObjects(
            chart
              ? { action: "chartData", ...draft }
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
          (!!chart && !!selected?.readOnlyReason)
        }
      >
        <legend>{t.chart}</legend>
        <label>
          {t.chartKind}
          <select
            aria-label={t.chartKind}
            value={draft.kind}
            onChange={(event) => {
              const kind = event.currentTarget.value;
              if (
                kind === "column" ||
                kind === "bar" ||
                kind === "line" ||
                kind === "pie"
              )
                setDraft({ ...draft, kind });
            }}
          >
            <option value="column">{t.chartColumn}</option>
            <option value="bar">{t.chartBar}</option>
            <option value="line">{t.chartLine}</option>
            <option value="pie">{t.chartPie}</option>
          </select>
        </label>
        <label>
          {t.chartTitle}
          <input
            aria-label={t.chartTitle}
            maxLength={256}
            value={draft.title}
            onChange={(event) =>
              setDraft({ ...draft, title: event.currentTarget.value })
            }
          />
        </label>
        <label>
          {t.chartData}
          <textarea
            aria-label={t.chartData}
            maxLength={65536}
            rows={6}
            value={draft.data}
            onChange={(event) =>
              setDraft({ ...draft, data: event.currentTarget.value })
            }
          />
        </label>
        <p>{t.chartDataHint}</p>
        {draft.kind === "pie" && <p>{t.chartPieHint}</p>}
        <button type="submit" disabled={!draft.data}>
          {chart ? t.chartApply : t.chartInsert}
        </button>
      </fieldset>
    </form>
  );
}
