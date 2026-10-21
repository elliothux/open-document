import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxShape,
  DocxShapePreset,
  DocxShapes as Shapes,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxDrawingPosition } from "./docx-drawing-position.js";
import { DocxTextBoxProperties } from "./docx-text-box-properties.js";
import { WordArt } from "./word-art.js";

export function DocxShapes({
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
  const [catalog, setCatalog] = useState<Shapes>();
  const [draft, setDraft] = useState<DocxShape>();
  const [creation, setCreation] = useState<{
    preset: DocxShapePreset | "textBox";
    width: number;
    height: number;
    text: string;
  }>({ preset: "rect", width: 120, height: 80, text: "" });
  const load = async (known?: ReadonlySet<number>) => {
    const value = await editor.shapes();
    setCatalog(value);
    setDraft(
      (known && value.items.find((item) => !known.has(item.id))) ??
        value.items.find((item) => item.id === draft?.id) ??
        value.items[0],
    );
  };
  const selection = editor.getSnapshot().data.selection;
  useEffect(() => {
    if (
      state.document?.composition ||
      state.document?.dragging ||
      state.document?.paused ||
      state.document?.stopped ||
      !selection ||
      selection.anchor.paragraph !== selection.focus.paragraph ||
      Math.abs(selection.anchor.offset - selection.focus.offset) !== 1
    )
      return;
    let active = true;
    controller.run(async () => {
      try {
        const value = await editor.shapes();
        const selected = value.items.find((item) => item.selected);
        if (active && selected) {
          setCatalog(value);
          setDraft(selected);
        }
      } catch (error) {
        if (active) throw error;
      }
    });
    return () => {
      active = false;
    };
  }, [
    controller,
    editor,
    state.document?.revision,
    state.document?.composition,
    state.document?.dragging,
    state.document?.paused,
    state.document?.stopped,
    selection?.anchor.paragraph,
    selection?.anchor.offset,
    selection?.focus.paragraph,
    selection?.focus.offset,
  ]);
  const shape = catalog?.items.find((item) => item.id === draft?.id);
  const stale = catalog?.revision !== state.document?.revision;
  return (
    <section aria-label={t.docxShapeProperties}>
      <h3>{t.docxShapeProperties}</h3>
      <WordArt
        controller={controller}
        state={state}
        disabled={disabled || !editor.getSnapshot().data.selection}
        apply={async (preset, text) => {
          const before = await editor.shapes();
          await editor.editShape(before.revision, {
            action: "insertWordArt",
            preset,
            text,
          });
          await load(new Set(before.items.map((item) => item.id)));
          editor.focus();
        }}
      />
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            const before = await editor.shapes();
            const { preset, text, ...size } = creation;
            await editor.editShape(before.revision, {
              action: "insert",
              ...size,
              preset: preset === "textBox" ? "rect" : preset,
              ...(preset === "textBox" ? { text } : {}),
              fill: preset === "textBox" ? "FFFFFF" : "4472C4",
              stroke: "000000",
              lineWidth: 1,
            });
            await load(new Set(before.items.map((item) => item.id)));
            if (preset === "textBox") editor.focus();
          });
        }}
      >
        <fieldset disabled={disabled || !editor.getSnapshot().data.selection}>
          <legend>{t.insertDocxShape}</legend>
          <label>
            {t.docxShapeKind}
            <select
              aria-label={t.docxShapeKind}
              value={creation.preset}
              onChange={(event) => {
                const preset = event.currentTarget.value;
                if (
                  preset === "rect" ||
                  preset === "ellipse" ||
                  preset === "line" ||
                  preset === "textBox"
                )
                  setCreation({
                    ...creation,
                    preset,
                    height: preset === "line" ? 0 : creation.height || 80,
                  });
              }}
            >
              <option value="rect">{t.docxShapeRectangle}</option>
              <option value="ellipse">{t.docxShapeEllipse}</option>
              <option value="line">{t.docxShapeLine}</option>
              <option value="textBox">{t.docxShapeTextBox}</option>
            </select>
          </label>
          {(
            [
              ["width", t.insertDocxShapeWidth],
              ["height", t.insertDocxShapeHeight],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                required
                step="any"
                min={creation.preset === "line" ? 0 : 1 / 12700}
                max={14400}
                value={Number.isFinite(creation[key]) ? creation[key] : ""}
                onChange={(event) =>
                  setCreation({
                    ...creation,
                    [key]: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
          ))}
          {creation.preset === "textBox" && (
            <label>
              {t.docxTextBoxInitialText}
              <textarea
                rows={3}
                maxLength={32767}
                value={creation.text}
                onChange={(event) =>
                  setCreation({ ...creation, text: event.currentTarget.value })
                }
              />
            </label>
          )}
          <button type="submit">
            {creation.preset === "textBox"
              ? t.insertDocxTextBox
              : t.insertDocxShape}
          </button>
        </fieldset>
      </form>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.loadDocxShapes}
      </button>
      {catalog && catalog.items.length > 0 && (
        <label>
          {t.chooseDocxShape}
          <select
            aria-label={t.chooseDocxShape}
            disabled={disabled || stale}
            value={draft?.id ?? ""}
            onChange={(event) =>
              setDraft(
                catalog.items.find(
                  (item) => item.id === Number(event.currentTarget.value),
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
      {shape?.reason && <p>{shape.reason}</p>}
      {draft && shape && (
        <>
          {shape.textBox && (
            <DocxTextBoxProperties
              key={`text:${shape.id}:${catalog?.revision}`}
              controller={controller}
              state={state}
              value={shape.textBox}
              reason={shape.textReason}
              disabled={disabled || stale}
              apply={async (properties) => {
                if (!catalog) return;
                await editor.editShape(catalog.revision, {
                  action: "textBox",
                  id: shape.id,
                  properties,
                });
                await load();
              }}
            />
          )}
          <DocxDrawingPosition
            key={`${shape.id}:${catalog?.revision}`}
            controller={controller}
            state={state}
            drawing={shape}
            disabled={disabled || stale}
            apply={async (anchor) => {
              if (!catalog) return;
              await editor.editShape(catalog.revision, {
                action: "position",
                id: shape.id,
                anchor,
              });
              await load();
            }}
          />
          <form
            onSubmit={(event) => {
              event.preventDefault();
              controller.run(async () => {
                if (!catalog) return;
                await editor.editShape(catalog.revision, {
                  action: "properties",
                  id: draft.id,
                  width: draft.width,
                  height: draft.height,
                  fill: draft.fill,
                  stroke: draft.stroke,
                  lineWidth: draft.lineWidth,
                });
                await load();
              });
            }}
          >
            <fieldset disabled={disabled || stale || !!shape.reason}>
              {(
                [
                  ["width", t.objectWidth],
                  ["height", t.objectHeight],
                  ["lineWidth", t.docxShapeLineWidth],
                ] as const
              ).map(([key, label]) => (
                <label key={key}>
                  {label}
                  <input
                    type="number"
                    required
                    step="any"
                    min={
                      key === "lineWidth" || shape.preset === "line"
                        ? 0
                        : 1 / 12700
                    }
                    max={key === "lineWidth" ? 1584 : 14400}
                    disabled={key !== "lineWidth" && !!shape.sizeReason}
                    title={key !== "lineWidth" ? shape.sizeReason : undefined}
                    value={Number.isFinite(draft[key]) ? draft[key] : ""}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        [key]: event.currentTarget.valueAsNumber,
                      })
                    }
                  />
                </label>
              ))}
              {(
                [
                  ["fill", t.docxShapeFill],
                  ["stroke", t.docxShapeStroke],
                ] as const
              ).map(([key, label]) => (
                <label key={key}>
                  {label}
                  <input
                    type="text"
                    pattern="[A-Fa-f0-9]{6}|"
                    maxLength={6}
                    value={draft[key]}
                    onChange={(event) =>
                      setDraft({ ...draft, [key]: event.currentTarget.value })
                    }
                  />
                </label>
              ))}
              <p>{t.docxShapeColorHint}</p>
              <button type="submit">{t.applyDocxShape}</button>
            </fieldset>
          </form>
          {shape.sizeReason && shape.sizeReason !== shape.reason && (
            <p>{shape.sizeReason}</p>
          )}
          <button
            type="button"
            disabled={disabled || stale || !!shape.deleteReason}
            title={shape.deleteReason}
            onClick={() =>
              controller.run(async () => {
                if (!catalog) return;
                await editor.editShape(catalog.revision, {
                  action: "delete",
                  id: shape.id,
                });
                await load();
              })
            }
          >
            {t.deleteDocxShape}
          </button>
          {shape.deleteReason && shape.deleteReason !== shape.reason && (
            <p>{shape.deleteReason}</p>
          )}
        </>
      )}
    </section>
  );
}
