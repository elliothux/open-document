import { DocxRunning } from "./docx-running.js";
import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxPageSettings,
  DocxPageSetup,
  DocxPageNumbering,
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
  const [draft, setDraft] = useState<DocxPageSetup>();
  const [numbering, setNumbering] = useState<DocxPageNumbering>({
    start: 1,
    format: "decimal",
  });
  const [color, setColor] = useState("#ffffff");
  const [orientation, setOrientation] = useState<"portrait" | "landscape">(
    "portrait",
  );
  const load = async () => {
    const value = await editor.pageSetup();
    setSettings(value);
    setDraft(value.page ?? undefined);
    setNumbering(value.numbering.value ?? { start: 1, format: "decimal" });
    setColor(`#${value.background.color ?? "ffffff"}`);
    setOrientation(
      value.page && value.page.width > value.page.height
        ? "landscape"
        : "portrait",
    );
  };
  const stale = settings?.revision !== state.document?.revision;
  return (
    <section aria-label={t.pageSetup}>
      <h3>{t.pageSetup}</h3>
      <DocxRunning
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
              await editor.setPageNumbering(numbering);
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || !!settings.numbering.reason}>
            <legend>{t.pageNumbering}</legend>
            <label>
              {t.pageNumberStart}
              <input
                type="number"
                min={0}
                max={4294967295}
                step={1}
                required
                value={Number.isFinite(numbering.start) ? numbering.start : ""}
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
                  await editor.setPageNumbering(null);
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
          key={settings.revision}
          value={settings.borders.value}
          reason={settings.borders.reason}
          disabled={disabled || stale}
          state={state}
          apply={(borders) =>
            controller.run(async () => {
              await editor.setPageBorders(borders);
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
          <fieldset disabled={disabled || stale}>
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
