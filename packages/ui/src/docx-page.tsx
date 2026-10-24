import { DocxRunning } from "./docx-running.js";
import { DocxBodyField } from "./docx-body-field.js";
import { DocxCaption } from "./docx-caption.js";
import { DocxNotes } from "./docx-notes.js";
import { DocxProtection } from "./docx-protection.js";
import { DocxCover } from "./docx-cover.js";
import { DocxWatermark } from "./docx-watermark.js";
import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxPageSettings,
  DocxPageSetup,
  DocxPageNumbering,
  DocxColumns,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxPageBordersForm } from "./docx-page-borders.js";
import { listFormats } from "@open-document/web/foundation";

export function DocxPage({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [settings, setSettings] = useState<DocxPageSettings>();
  const [section, setSection] = useState(0);
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
    const value = await editor.pageSetup(index);
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
  return (
    <section aria-label={t.pageSetup}>
      <h3>{t.pageSetup}</h3>
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
      <button
        type="button"
        disabled={disabled || !editor.getSnapshot().data.selection}
        onClick={() =>
          controller.run(() => editor.insertBodyPageField({ field: "PAGE" }))
        }
      >
        {t.insertBodyPageNumber}
      </button>
      <button
        type="button"
        disabled={disabled || !editor.getSnapshot().data.selection}
        onClick={() =>
          controller.run(() =>
            editor.insertBodyPageField({ field: "NUMPAGES" }),
          )
        }
      >
        {t.insertBodyPageCount}
      </button>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(() => editor.updateBodyPageFields())}
      >
        {t.updateBodyPageFields}
      </button>
      <DocxRunning
        key={section}
        section={section}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <DocxBodyField
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
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
      <DocxCover
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <DocxWatermark
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <DocxProtection
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.loadPageSetup}
      </button>
      {settings?.reason && <p>{settings.reason}</p>}
      {settings && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setPageColumns(section, columns);
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
            <legend>{t.pageColumns}</legend>
            <label>
              {t.columnCount}
              <input
                type="number"
                min={1}
                max={12}
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
                      count <= 12
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
                            columns.count <= 12
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
              const width = last
                ? Math.round(
                    (fullWidth -
                      columns.custom
                        .slice(0, index)
                        .reduce(
                          (sum, column) => sum + column.width + column.gap,
                          0,
                        )) *
                      20,
                  ) / 20
                : column.width;
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
            <button type="submit">{t.applyPageColumns}</button>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.setPageColumns(section, null);
                  await load();
                })
              }
            >
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
              await editor.setPageNumbering(section, numbering);
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
            <legend>{t.pageNumbering}</legend>
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
                max={4294967295}
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
            <button type="submit">{t.applyPageNumbering}</button>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.setPageNumbering(section, null);
                  await load();
                })
              }
            >
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
              await editor.setPageBorders(section, borders);
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
              await editor.setPageBackground(color.slice(1));
              await load();
            });
          }}
        >
          <fieldset
            disabled={disabled || stale || !!settings.background.reason}
          >
            <legend>{t.pageBackground}</legend>
            <label>
              {t.pageBackground}
              <input
                type="color"
                value={color}
                onChange={(event) => setColor(event.currentTarget.value)}
              />
            </label>
            <button type="submit">{t.applyPageBackground}</button>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.setPageBackground(null);
                  await load();
                })
              }
            >
              {t.resetPageBackground}
            </button>
          </fieldset>
          {settings.background.reason && <p>{settings.background.reason}</p>}
        </form>
      )}
      {draft && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setPageSetup({ ...draft, orientation });
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || draft.section !== section}>
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
              {t.applyPageSetup}
            </button>
          </fieldset>
          {stale && <p>{t.reloadPageSetup}</p>}
        </form>
      )}
    </section>
  );
}
