import { DocxRunning } from "./docx-running.js";
import { DocxBodyField } from "./docx-body-field.js";
import { DocxCaption } from "./docx-caption.js";
import { DocxNotes } from "./docx-notes.js";
import { DocxNoteNumbering } from "./docx-note-numbering.js";
import { DocxCover } from "./docx-cover.js";
import { DocxWatermark } from "./docx-watermark.js";
import { useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import type {
  DocxPageSettings,
  DocxPageSetup,
  DocxPageNumbering,
  DocxColumns,
  DocxSectionBreak,
} from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import {
  docxNumberingStartMax,
  docxPageColumnCount,
} from "@open-document/wasm/engine-source";
import { DocxPageBordersForm } from "./docx-page-borders.js";
import { listFormats } from "../web/foundation.js";
import { Icon } from "@open-document/ui/icons";

export function DocxPage({
  controller,
  state,
  editor,
  disabled,
  task = "layout",
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  task?: "layout" | "running" | "notes";
}) {
  const t = messages(state.locale);
  const [settings, setSettings] = useState<DocxPageSettings>();
  const [section, setSection] = useState(0);
  const [sectionBreak, setSectionBreak] =
    useState<DocxSectionBreak>("nextPage");
  const [draft, setDraft] = useState<DocxPageSetup>();
  const [numbering, setNumbering] = useState<DocxPageNumbering>({
    start: null,
    format: "decimal",
  });
  const [color, setColor] = useState("#ffffff");
  const [columns, setColumns] = useState<DocxColumns>({
    count: 1,
    gap: 36,
    separator: false,
    custom: [],
  });
  const [orientation, setOrientation] = useState<"portrait" | "landscape">(
    "portrait",
  );
  const load = async (index = section) => {
    const value = await editor.pages.pageSetup(index);
    setSettings(value);
    setDraft(value.page ?? undefined);
    setNumbering(value.numbering.value ?? { start: null, format: "decimal" });
    setColumns(
      value.columns.value ?? {
        count: 1,
        gap: 36,
        separator: false,
        custom: [],
      },
    );
    setColor(`#${value.background.color ?? "ffffff"}`);
    setOrientation(
      value.page && value.page.width > value.page.height
        ? "landscape"
        : "portrait",
    );
  };
  const stale = settings?.revision !== state.document?.revision;
  const fullWidth = settings?.columns.availableWidth ?? 468;
  const lastColumnWidth =
    Math.round(
      (fullWidth -
        columns.custom
          .slice(0, -1)
          .reduce((sum, column) => sum + column.width + column.gap, 0)) *
        20,
    ) / 20;
  const customColumns = (count: number) =>
    Array.from(
      { length: count },
      (_, index) =>
        columns.custom[index] ?? {
          width: Math.max(
            12,
            Math.floor(((fullWidth - columns.gap * (count - 1)) * 20) / count) /
              20,
          ),
          gap: columns.gap,
        },
    );
  const sectionChooser = (
    <>
      {settings && settings.sectionCount > 1 && (
        <label>
          {t.pageSection}
          <select
            aria-label={t.pageSection}
            value={section}
            disabled={disabled}
            onChange={(event) => {
              const index = Number(event.currentTarget.value);
              setSection(index);
              controller.run(() => load(index));
            }}
          >
            {Array.from({ length: settings.sectionCount }, (_, index) => (
              <option key={index} value={index}>
                {t.pageSectionLabel} {index + 1}
              </option>
            ))}
          </select>
        </label>
      )}
    </>
  );
  if (task !== "layout")
    return (
      <section
        aria-label={task === "running" ? t.headerFooterTab : t.noteNumbering}
      >
        {sectionChooser}
        {!settings && (
          <button
            type="button"
            disabled={disabled}
            onClick={() => controller.run(load)}
          >
            <Icon name="refresh" />
            {t.loadPageSetup}
          </button>
        )}
        {task === "running" ? (
          <DocxRunning
            key={`running:${section}`}
            section={section}
            controller={controller}
            state={state}
            editor={editor}
            disabled={disabled}
          />
        ) : (
          <>
            <DocxCaption
              controller={controller}
              state={state}
              editor={editor}
              disabled={disabled}
            />
            <DocxNotes
              controller={controller}
              state={state}
              editor={editor}
              disabled={disabled}
            />
            <DocxNoteNumbering
              key={`note-numbering:${section}`}
              section={section}
              controller={controller}
              state={state}
              editor={editor}
              disabled={disabled}
            />
          </>
        )}
      </section>
    );
  return (
    <section aria-label={t.pageSetup}>
      <h3>
        <Icon name="ruler" />
        {t.pageSetup}
      </h3>
      {sectionChooser}
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        <Icon name="refresh" />
        {t.loadPageSetup}
      </button>
      {settings?.reason && <p>{settings.reason}</p>}
      {draft && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.pages.setPageSetup({ ...draft, orientation });
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || draft.section !== section}>
            <label>
              {t.footnotesPosition}
              <select
                aria-label={t.footnotesPosition}
                value={draft.footnotesAt}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    footnotesAt:
                      event.currentTarget.value === "beneathText"
                        ? "beneathText"
                        : "pageBottom",
                  })
                }
              >
                <option value="pageBottom">{t.footnotesPageBottom}</option>
                <option value="beneathText">{t.footnotesBeneathText}</option>
              </select>
            </label>
            <label>
              {t.sectionStartType}
              <select
                aria-label={t.sectionStartType}
                value={draft.startType}
                onChange={(event) => {
                  const value = event.currentTarget.value;
                  setDraft({
                    ...draft,
                    startType:
                      value === "continuous" ||
                      value === "oddPage" ||
                      value === "evenPage"
                        ? value
                        : "nextPage",
                  });
                }}
              >
                <option value="nextPage">{t.sectionBreakNext}</option>
                <option value="continuous">{t.sectionBreakContinuous}</option>
                <option value="oddPage">{t.sectionBreakOdd}</option>
                <option value="evenPage">{t.sectionBreakEven}</option>
              </select>
            </label>
            <label>
              {t.pageOrientation}
              <select
                aria-label={t.pageOrientation}
                value={orientation}
                onChange={(event) => {
                  setOrientation(
                    event.currentTarget.value === "landscape"
                      ? "landscape"
                      : "portrait",
                  );
                }}
              >
                <option value="portrait">{t.portrait}</option>
                <option value="landscape">{t.landscape}</option>
              </select>
            </label>
            <label>
              {t.marginPresets}
              <select
                aria-label={t.marginPresets}
                value={
                  draft.top === 72 &&
                  draft.bottom === 72 &&
                  draft.left === 72 &&
                  draft.right === 72
                    ? "72"
                    : draft.top === 36 &&
                        draft.bottom === 36 &&
                        draft.left === 36 &&
                        draft.right === 36
                      ? "36"
                      : ""
                }
                onChange={(event) => {
                  const margin = Number(event.currentTarget.value);
                  setDraft({
                    ...draft,
                    top: margin,
                    right: margin,
                    bottom: margin,
                    left: margin,
                  });
                }}
              >
                <option value="" disabled>
                  {t.customMargins}
                </option>
                <option value="72">{t.normalMargins}</option>
                <option value="36">{t.narrowMargins}</option>
              </select>
            </label>
            {(
              [
                ["width", t.pageWidth],
                ["height", t.pageHeight],
                ["top", t.pageTop],
                ["right", t.pageRight],
                ["bottom", t.pageBottom],
                ["left", t.pageLeft],
              ] as const
            ).map(([key, label]) => (
              <label key={key}>
                {label}
                <input
                  type="number"
                  min={key === "width" || key === "height" ? 36 : 0}
                  max={14400}
                  step={0.05}
                  required
                  value={Number.isFinite(draft[key]) ? draft[key] : ""}
                  onChange={(event) => {
                    const value = {
                      ...draft,
                      [key]: event.currentTarget.valueAsNumber,
                    };
                    setDraft(value);
                    if (key === "width" || key === "height")
                      setOrientation(
                        value.width > value.height ? "landscape" : "portrait",
                      );
                  }}
                />
              </label>
            ))}
            <button
              type="submit"
              disabled={
                draft.width - draft.left - draft.right < 12 ||
                draft.height - draft.top - draft.bottom < 12
              }
            >
              <Icon name="check" />
              {t.applyPageSetup}
            </button>
          </fieldset>
          {stale && <p>{t.reloadPageSetup}</p>}
        </form>
      )}
      <label>
        {t.sectionBreakType}
        <select
          aria-label={t.sectionBreakType}
          disabled={disabled}
          value={sectionBreak}
          onChange={(event) => {
            const value = event.currentTarget.value;
            setSectionBreak(
              value === "oddPage" ||
                value === "evenPage" ||
                value === "continuous"
                ? value
                : "nextPage",
            );
          }}
        >
          <option value="nextPage">{t.sectionBreakNext}</option>
          <option value="continuous">{t.sectionBreakContinuous}</option>
          <option value="oddPage">{t.sectionBreakOdd}</option>
          <option value="evenPage">{t.sectionBreakEven}</option>
        </select>
      </label>
      <button
        type="button"
        disabled={disabled || !editor.getSnapshot().data.selection}
        onClick={() =>
          controller.run(async () => {
            await editor.pages.insertSectionBreak(sectionBreak);
            await load();
          })
        }
      >
        <Icon name="plus" />
        {t.insertSectionBreak}
      </button>
      <button
        type="button"
        disabled={disabled || !editor.getSnapshot().data.selection}
        onClick={() =>
          controller.run(() =>
            editor.pages.insertBodyPageField({ field: "PAGE" }),
          )
        }
      >
        <Icon name="plus" />
        {t.insertBodyPageNumber}
      </button>
      <button
        type="button"
        disabled={disabled || !editor.getSnapshot().data.selection}
        onClick={() =>
          controller.run(() =>
            editor.pages.insertBodyPageField({ field: "NUMPAGES" }),
          )
        }
      >
        <Icon name="plus" />
        {t.insertBodyPageCount}
      </button>
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() => editor.pages.updateBodyPageFields())
        }
      >
        <Icon name="refresh" />
        {t.updateBodyPageFields}
      </button>
      <DocxBodyField
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <DocxCover
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <DocxWatermark
        key={section}
        section={section}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      {settings && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.pages.setPageColumns(section, {
                ...columns,
                custom: columns.custom.map((column, index) =>
                  index === columns.custom.length - 1
                    ? { ...column, width: lastColumnWidth }
                    : column,
                ),
              });
              await load();
            });
          }}
        >
          <fieldset
            disabled={
              disabled ||
              stale ||
              !!settings.columns.reason ||
              settings.page?.section !== section
            }
          >
            <legend>
              <Icon name="columns-2" />
              {t.pageColumns}
            </legend>
            <label>
              {t.columnCount}
              <input
                type="number"
                min={1}
                max={docxPageColumnCount}
                step={1}
                required
                value={Number.isFinite(columns.count) ? columns.count : ""}
                onChange={(event) => {
                  const count = event.currentTarget.valueAsNumber;
                  setColumns({
                    ...columns,
                    count,
                    custom:
                      columns.custom.length &&
                      Number.isInteger(count) &&
                      count >= 1 &&
                      count <= docxPageColumnCount
                        ? customColumns(count)
                        : columns.custom,
                  });
                }}
              />
            </label>
            <label>
              <input
                type="checkbox"
                checked={columns.custom.length === 0}
                onChange={(event) =>
                  setColumns({
                    ...columns,
                    custom: event.currentTarget.checked
                      ? []
                      : customColumns(
                          Number.isInteger(columns.count) &&
                            columns.count >= 1 &&
                            columns.count <= docxPageColumnCount
                            ? columns.count
                            : 2,
                        ),
                  })
                }
              />
              {t.equalColumnWidths}
            </label>
            <label>
              {t.columnGap}
              <input
                type="number"
                min={0}
                max={14400}
                step={0.05}
                required
                disabled={columns.custom.length > 0}
                value={Number.isFinite(columns.gap) ? columns.gap : ""}
                onChange={(event) =>
                  setColumns({
                    ...columns,
                    gap: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
            {columns.custom.map((column, index) => {
              const last = index === columns.custom.length - 1;
              const width = last ? lastColumnWidth : column.width;
              return (
                <fieldset key={index}>
                  <legend>
                    {t.customColumn} {index + 1}
                  </legend>
                  <label>
                    {t.customColumnWidth}
                    <input
                      type="number"
                      min={12}
                      max={14400}
                      step={0.05}
                      required
                      readOnly={last}
                      value={Number.isFinite(width) ? width : ""}
                      onChange={(event) =>
                        setColumns({
                          ...columns,
                          custom: columns.custom.map((column, i) =>
                            i === index
                              ? {
                                  ...column,
                                  width: event.currentTarget.valueAsNumber,
                                }
                              : column,
                          ),
                        })
                      }
                    />
                  </label>
                  {!last && (
                    <label>
                      {t.columnGap}
                      <input
                        type="number"
                        min={0}
                        max={14400}
                        step={0.05}
                        required
                        value={Number.isFinite(column.gap) ? column.gap : ""}
                        onChange={(event) =>
                          setColumns({
                            ...columns,
                            custom: columns.custom.map((column, i) =>
                              i === index
                                ? {
                                    ...column,
                                    gap: event.currentTarget.valueAsNumber,
                                  }
                                : column,
                            ),
                          })
                        }
                      />
                    </label>
                  )}
                  {last && <p>{t.lastColumnWidth}</p>}
                </fieldset>
              );
            })}
            <label>
              <input
                type="checkbox"
                checked={columns.separator}
                onChange={(event) =>
                  setColumns({
                    ...columns,
                    separator: event.currentTarget.checked,
                  })
                }
              />
              {t.columnSeparator}
            </label>
            <button type="submit">
              <Icon name="check" />
              {t.applyPageColumns}
            </button>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.pages.setPageColumns(section, null);
                  await load();
                })
              }
            >
              <Icon name="undo" />
              {t.resetPageColumns}
            </button>
          </fieldset>
          {settings.columns.reason && <p>{settings.columns.reason}</p>}
        </form>
      )}
      {settings && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.pages.setPageNumbering(section, numbering);
              await load();
            });
          }}
        >
          <fieldset
            disabled={
              disabled ||
              stale ||
              !!settings.numbering.reason ||
              settings.page?.section !== section
            }
          >
            <legend>
              <Icon name="number-format" />
              {t.pageNumbering}
            </legend>
            <label>
              <input
                type="checkbox"
                checked={numbering.start !== null}
                onChange={(event) =>
                  setNumbering({
                    ...numbering,
                    start: event.currentTarget.checked ? 1 : null,
                  })
                }
              />
              {t.restartPageNumbering}
            </label>
            <label>
              {t.pageNumberStart}
              <input
                type="number"
                min={0}
                max={docxNumberingStartMax}
                step={1}
                required
                disabled={numbering.start === null}
                value={
                  numbering.start === null
                    ? 1
                    : Number.isFinite(numbering.start)
                      ? numbering.start
                      : ""
                }
                onChange={(event) =>
                  setNumbering({
                    ...numbering,
                    start: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
            <label>
              {t.pageNumberFormat}
              <select
                value={numbering.format}
                onChange={(event) =>
                  setNumbering({
                    ...numbering,
                    format: event.currentTarget
                      .value as DocxPageNumbering["format"],
                  })
                }
              >
                {listFormats
                  .filter((format) => format !== "bullet")
                  .map((format) => (
                    <option key={format} value={format}>
                      {t[`listFormat_${format}`]}
                    </option>
                  ))}
              </select>
            </label>
            <button type="submit">
              <Icon name="check" />
              {t.applyPageNumbering}
            </button>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.pages.setPageNumbering(section, null);
                  await load();
                })
              }
            >
              <Icon name="undo" />
              {t.resetPageNumbering}
            </button>
          </fieldset>
          {settings.numbering.reason && <p>{settings.numbering.reason}</p>}
        </form>
      )}
      {settings && (
        <DocxPageBordersForm
          key={`${settings.revision}:${settings.page?.section ?? -1}`}
          value={settings.borders.value}
          reason={settings.borders.reason}
          disabled={disabled || stale || settings.page?.section !== section}
          state={state}
          apply={(borders) =>
            controller.run(async () => {
              await editor.pages.setPageBorders(section, borders);
              await load();
            })
          }
        />
      )}
      {settings && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.pages.setPageBackground(color.slice(1));
              await load();
            });
          }}
        >
          <fieldset
            disabled={disabled || stale || !!settings.background.reason}
          >
            <legend>
              <Icon name="paint-bucket" />
              {t.pageBackground}
            </legend>
            <label>
              {t.pageBackground}
              <input
                type="color"
                value={color}
                onChange={(event) => setColor(event.currentTarget.value)}
              />
            </label>
            <button type="submit">
              <Icon name="check" />
              {t.applyPageBackground}
            </button>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.pages.setPageBackground(null);
                  await load();
                })
              }
            >
              <Icon name="undo" />
              {t.resetPageBackground}
            </button>
          </fieldset>
          {settings.background.reason && <p>{settings.background.reason}</p>}
        </form>
      )}
    </section>
  );
}
