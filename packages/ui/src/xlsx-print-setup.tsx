import { useState, type ReactNode } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { Command, Group } from "./controls.js";

type PrintProps = {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
};

export function XlsxPrintCommands({
  controller,
  state,
  editor,
  disabled,
  navigation,
}: PrintProps & { navigation: ReactNode }) {
  const t = messages(state.locale),
    visible = editor.getSnapshot().data.printVisible;
  return (
    <Group label={t.print}>
      <Command
        label={visible ? t.closePrint : t.print}
        disabled={disabled}
        action={() =>
          controller.run(() =>
            visible ? editor.closePrintPreview() : editor.printLayout(),
          )
        }
      />
      <Command
        label={t.printWorkbook}
        disabled={disabled}
        action={() =>
          controller.run(() => editor.printLayout({ sheets: "visible" }))
        }
      />
      {visible && navigation}
    </Group>
  );
}

export function XlsxPrintSetup({
  controller,
  state,
  editor,
  disabled,
}: PrintProps) {
  const t = messages(state.locale),
    current = editor.currentState.printSetup;
  const [paper, setPaper] = useState(current.paper),
    [orientation, setOrientation] = useState(current.orientation);
  const [values, setValues] = useState({
    left: String(current.left),
    top: String(current.top),
    right: String(current.right),
    bottom: String(current.bottom),
    scale: String(current.scale),
    fitWidth: String(current.fitWidth),
    fitHeight: String(current.fitHeight),
  });
  const currentRange = editor.currentState.printRange;
  const currentHeaders = editor.currentState.headerFooter;
  const { readOnlyReason: headerReason, ...headerSettings } = currentHeaders;
  const [headers, setHeaders] = useState(headerSettings);
  const [distances, setDistances] = useState({
    headerMargin: String(headerSettings.headerMargin),
    footerMargin: String(headerSettings.footerMargin),
  });
  const [range, setRange] = useState({
    area: currentRange.area,
    rows: currentRange.rows,
    columns: currentRange.columns,
  });
  const draftDisabled =
    state.loading ||
    !!state.document?.paused ||
    !!state.document?.composition ||
    !!state.document?.dragging ||
    !!state.document?.closed;
  return (
    <>
      <fieldset disabled={draftDisabled || !!current.readOnlyReason}>
        <legend>{t.sheetPrintSetup}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.editSheet({
                action: "pageSetup",
                paper,
                orientation,
                left: Number(values.left),
                top: Number(values.top),
                right: Number(values.right),
                bottom: Number(values.bottom),
                scale: Number(values.scale),
                fitWidth: Number(values.fitWidth),
                fitHeight: Number(values.fitHeight),
              });
            });
          }}
        >
          <label>
            {t.printPaper}
            <select
              aria-label={t.printPaper}
              value={paper}
              onChange={(event) => {
                const value = event.currentTarget.value;
                if (value === "A4" || value === "Letter") setPaper(value);
              }}
            >
              <option value="A4">A4</option>
              <option value="Letter">Letter</option>
            </select>
          </label>
          <label>
            {t.pageOrientation}
            <select
              aria-label={t.pageOrientation}
              value={orientation}
              onChange={(event) => {
                const value = event.currentTarget.value;
                if (value === "portrait" || value === "landscape")
                  setOrientation(value);
              }}
            >
              <option value="portrait">{t.portrait}</option>
              <option value="landscape">{t.landscape}</option>
            </select>
          </label>
          {(
            [
              ["left", t.pageLeft],
              ["top", t.pageTop],
              ["right", t.pageRight],
              ["bottom", t.pageBottom],
              ["scale", t.printScale],
              ["fitWidth", t.printFitWidth],
              ["fitHeight", t.printFitHeight],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                required
                step={
                  key === "scale" || key === "fitWidth" || key === "fitHeight"
                    ? 1
                    : "any"
                }
                min={key === "scale" ? 10 : 0}
                max={
                  key === "scale"
                    ? 400
                    : key === "fitWidth" || key === "fitHeight"
                      ? 1024
                      : 14400
                }
                value={values[key]}
                onChange={(event) => {
                  const value = event.currentTarget.value;
                  setValues((previous) => ({
                    ...previous,
                    [key]: value,
                  }));
                }}
              />
            </label>
          ))}
          <p>{t.printFitNotice}</p>
          <button type="submit" disabled={disabled}>
            {t.apply} {t.sheetPrintSetup}
          </button>
        </form>
        {current.readOnlyReason && <p>{current.readOnlyReason}</p>}
      </fieldset>
      <fieldset disabled={draftDisabled || !!currentRange.readOnlyReason}>
        <legend>{t.sheetPrintRange}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.editSheet({ action: "printRange", ...range });
            });
          }}
        >
          {(
            [
              ["area", t.printArea, "A1:D20,F1:H20"],
              ["rows", t.printTitleRows, "1:2"],
              ["columns", t.printTitleColumns, "A:B"],
            ] as const
          ).map(([key, label, placeholder]) => (
            <label key={key}>
              {label}
              <input
                value={range[key]}
                placeholder={placeholder}
                maxLength={key === "area" ? 2048 : 32}
                onChange={(event) => {
                  const value = event.currentTarget.value;
                  setRange((previous) => ({ ...previous, [key]: value }));
                }}
              />
            </label>
          ))}
          <p>{t.printRangeNotice}</p>
          <button type="submit" disabled={disabled}>
            {t.apply} {t.sheetPrintRange}
          </button>
        </form>
        {currentRange.readOnlyReason && <p>{currentRange.readOnlyReason}</p>}
      </fieldset>
      <fieldset disabled={draftDisabled || !!headerReason}>
        <legend>{t.sheetHeaderFooter}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.editSheet({
                action: "headerFooter",
                ...headers,
                headerMargin: Number(distances.headerMargin),
                footerMargin: Number(distances.footerMargin),
              });
            });
          }}
        >
          {(
            [
              ["oddHeader", t.header],
              ["oddFooter", t.footer],
              ["evenHeader", t.evenHeader],
              ["evenFooter", t.evenFooter],
              ["firstHeader", t.firstHeader],
              ["firstFooter", t.firstFooter],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <textarea
                aria-label={label}
                value={headers[key]}
                maxLength={255}
                onChange={(event) => {
                  const value = event.currentTarget.value;
                  setHeaders((previous) => ({ ...previous, [key]: value }));
                }}
              />
            </label>
          ))}
          {(
            [
              ["differentFirst", t.headerDifferentFirst],
              ["differentOddEven", t.headerDifferentOddEven],
              ["scaleWithDoc", t.headerScale],
              ["alignWithMargins", t.headerAlign],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              <input
                type="checkbox"
                checked={headers[key]}
                onChange={(event) => {
                  const value = event.currentTarget.checked;
                  setHeaders((previous) => ({ ...previous, [key]: value }));
                }}
              />
              {label}
            </label>
          ))}
          {(
            [
              ["headerMargin", t.headerDistance],
              ["footerMargin", t.footerDistance],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                required
                min={0}
                max={14400}
                step="any"
                value={distances[key]}
                onChange={(event) => {
                  const value = event.currentTarget.value;
                  setDistances((previous) => ({ ...previous, [key]: value }));
                }}
              />
            </label>
          ))}
          <p>{t.headerFooterNotice}</p>
          <button type="submit" disabled={disabled}>
            {t.apply} {t.sheetHeaderFooter}
          </button>
        </form>
        {headerReason && <p>{headerReason}</p>}
      </fieldset>
    </>
  );
}
