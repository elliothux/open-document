import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  xlsxChartKinds,
  type XlsxChart,
  type XlsxCharts as Catalog,
  type XlsxChartSettings,
} from "@open-document/web/xlsx";
import type { ChartSettings } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { ChartFields } from "./chart-fields.js";
import { messages } from "./messages.js";

function settings(value: XlsxChart): XlsxChartSettings {
  return {
    kind: value.kind,
    title: value.title,
    label: value.label,
    legend: value.legend,
    holeSize: value.holeSize,
    categories: value.categories,
    names: value.names,
    values: value.values,
  };
}

export function XlsxCharts({
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
  const t = messages(state.locale);
  const [range, setRange] = useState("");
  const [kind, setKind] = useState<XlsxChartSettings["kind"]>("column");
  const [title, setTitle] = useState(t.chart);
  const [size, setSize] = useState({ width: 480, height: 300 });
  const [catalog, setCatalog] = useState<Catalog>();
  const [draft, setDraft] = useState<XlsxChart>();
  const load = async (last = false) => {
    const value = await editor.charts();
    setCatalog(value);
    setDraft(
      (last
        ? value.items.at(-1)
        : value.items.find((item) => item.id === draft?.id)) ?? value.items[0],
    );
  };
  const stale =
    catalog?.revision !== state.document?.revision ||
    catalog?.sheet !== editor.currentState.sheet;
  const names = {
    column: t.chartColumn,
    bar: t.chartBar,
    stackedColumn: t.chartStackedColumn,
    stackedBar: t.chartStackedBar,
    percentStackedColumn: t.chartPercentStackedColumn,
    percentStackedBar: t.chartPercentStackedBar,
    line: t.chartLine,
    stackedLine: t.chartStackedLine,
    percentStackedLine: t.chartPercentStackedLine,
    pie: t.chartPie,
    area: t.chartArea,
    stackedArea: t.chartStackedArea,
    percentStackedArea: t.chartPercentStackedArea,
    scatter: t.chartScatter,
    radar: t.chartRadar,
    doughnut: t.chartDoughnut,
  };
  const appearance: ChartSettings | undefined = draft
    ? {
        kind: draft.kind,
        title: draft.title,
        data: draft.data,
        legend: draft.legend,
        ...(draft.holeSize === null ? {} : { holeSize: draft.holeSize }),
      }
    : undefined;
  return (
    <section aria-label={t.worksheetCharts}>
      <h3>{t.worksheetCharts}</h3>
      <p>{t.chartRangeHint}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            await editor.insertChartRange(
              range || editor.currentState.selection.address,
              kind,
              title,
              size.width,
              size.height,
            );
            await load(true);
          });
        }}
      >
        <fieldset disabled={disabled}>
          <legend>{t.chartInsert}</legend>
          <label>
            {t.cellRange}
            <input
              aria-label={t.cellRange}
              value={range}
              placeholder={editor.currentState.selection.address}
              maxLength={256}
              onChange={(event) => setRange(event.currentTarget.value)}
            />
          </label>
          <button
            type="button"
            onClick={() => setRange(editor.currentState.selection.address)}
          >
            {t.nameFromSelection}
          </button>
          <label>
            {t.chartKind}
            <select
              aria-label={t.chartKind}
              value={kind}
              onChange={(event) => {
                const next = xlsxChartKinds.find(
                  (kind) => kind === event.currentTarget.value,
                );
                if (next) setKind(next);
              }}
            >
              {xlsxChartKinds.map((kind) => (
                <option key={kind} value={kind}>
                  {names[kind]}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t.chartTitle}
            <input
              value={title}
              maxLength={256}
              onChange={(event) => setTitle(event.currentTarget.value)}
            />
          </label>
          {(
            [
              ["width", t.objectWidth],
              ["height", t.objectHeight],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                min={key === "width" ? 180 : 150}
                max={14400}
                required
                value={size[key]}
                onChange={(event) =>
                  setSize({ ...size, [key]: event.currentTarget.valueAsNumber })
                }
              />
            </label>
          ))}
          <button type="submit">{t.chartInsert}</button>
        </fieldset>
      </form>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(() => load())}
      >
        {t.chartLoad}
      </button>
      {catalog?.reason && <p>{catalog.reason}</p>}
      {!!catalog?.items.length && (
        <label>
          {t.chartChoose}
          <select
            aria-label={t.chartChoose}
            value={draft?.id ?? ""}
            onChange={(event) =>
              setDraft(
                catalog.items.find(
                  (item) => item.id === event.currentTarget.value,
                ),
              )
            }
          >
            {catalog.items.map((item) => (
              <option key={item.id} value={item.id}>
                {item.name}
              </option>
            ))}
          </select>
        </label>
      )}
      {draft && appearance && (
        <>
          {draft.bindingReason && <p>{t.chartCachedSource}</p>}
          <form
            onSubmit={(event) => {
              event.preventDefault();
              controller.run(async () => {
                await editor.setChart(draft.id, settings(draft));
                await load();
              });
            }}
          >
            <fieldset disabled={disabled || stale || !!catalog?.reason}>
              <legend>{t.chartApply}</legend>
              <ChartFields
                draft={appearance}
                t={t}
                setDraft={(value) =>
                  setDraft({
                    ...draft,
                    kind: value.kind,
                    title: value.title,
                    legend: value.legend ?? "bottom",
                    holeSize: value.holeSize ?? null,
                  })
                }
              >
                <label>
                  {t.chartAxisLabel}
                  <input
                    maxLength={256}
                    value={draft.label}
                    onChange={(event) =>
                      setDraft({ ...draft, label: event.currentTarget.value })
                    }
                  />
                </label>
                <label>
                  {t.chartCategorySource}
                  <input
                    required
                    maxLength={1024}
                    value={draft.categories}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        categories: event.currentTarget.value,
                      })
                    }
                  />
                </label>
                {(
                  [
                    ["names", t.chartNameSources],
                    ["values", t.chartValueSources],
                  ] as const
                ).map(([key, label]) => (
                  <label key={key}>
                    {label}
                    <textarea
                      aria-label={label}
                      required
                      rows={3}
                      maxLength={8199}
                      value={draft[key].join("\n")}
                      onChange={(event) =>
                        setDraft({
                          ...draft,
                          [key]: event.currentTarget.value.split("\n"),
                        })
                      }
                    />
                  </label>
                ))}
                <label>
                  {t.chartData}
                  <textarea
                    aria-label={t.chartData}
                    rows={4}
                    readOnly
                    value={draft.data}
                  />
                </label>
              </ChartFields>
              <button type="submit">{t.chartApply}</button>
            </fieldset>
          </form>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              controller.run(async () => {
                await editor.setChartFrame(draft.id, draft);
                await load();
              });
            }}
          >
            <fieldset disabled={disabled || stale || !!catalog?.reason}>
              <legend>{t.chartResize}</legend>
              <label>
                {t.xlsxShapeName}
                <input
                  required
                  maxLength={255}
                  value={draft.name}
                  onChange={(event) =>
                    setDraft({ ...draft, name: event.currentTarget.value })
                  }
                />
              </label>
              <label>
                {t.xlsxPictureAlt}
                <input
                  maxLength={1024}
                  value={draft.description}
                  onChange={(event) =>
                    setDraft({
                      ...draft,
                      description: event.currentTarget.value,
                    })
                  }
                />
              </label>
              <label>
                {t.xlsxShapeAnchor}
                <select
                  aria-label={t.xlsxShapeAnchor}
                  value={draft.anchor}
                  onChange={(event) => {
                    const anchor = event.currentTarget.value;
                    if (
                      anchor === "fixed" ||
                      anchor === "move" ||
                      anchor === "size"
                    )
                      setDraft({ ...draft, anchor });
                  }}
                >
                  <option value="fixed">{t.xlsxPictureFixed}</option>
                  <option value="move">{t.xlsxPictureMove}</option>
                  <option value="size">{t.xlsxPictureSize}</option>
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
                    required
                    type="number"
                    step="any"
                    min={
                      key === "x" || key === "y"
                        ? 0
                        : key === "width"
                          ? 180
                          : 150
                    }
                    max={key === "x" || key === "y" ? 1e9 : 14400}
                    value={draft[key]}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        [key]: event.currentTarget.valueAsNumber,
                      })
                    }
                  />
                </label>
              ))}
              <button type="submit">{t.chartResize}</button>
              <button
                type="button"
                onClick={() =>
                  controller.run(async () => {
                    await editor.deleteChart(draft.id);
                    await load();
                  })
                }
              >
                {t.chartDelete}
              </button>
              <button
                type="button"
                onClick={() =>
                  controller.run(async () => {
                    await editor.editSheet({
                      action: "duplicateDrawing",
                      objectId: draft.id,
                    });
                    await load(true);
                  })
                }
              >
                {t.duplicateObject}
              </button>
              <button
                type="button"
                onClick={() =>
                  controller.run(() => editor.copyDrawing(draft.id))
                }
              >
                {t.copyDrawing}
              </button>
              <button
                type="button"
                onClick={() =>
                  controller.run(() => editor.cutDrawing(draft.id))
                }
              >
                {t.cutDrawing}
              </button>
            </fieldset>
          </form>
        </>
      )}
    </section>
  );
}
