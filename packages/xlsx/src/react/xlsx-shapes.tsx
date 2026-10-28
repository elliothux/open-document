import { useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import {
  xlsxShapeKinds,
  checkXlsxShapeSettings,
  type XlsxShapeKind,
  type XlsxShape,
  type XlsxShapes as Catalog,
} from "../web/xlsx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function XlsxShapes({
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
  const [kind, setKind] = useState<XlsxShapeKind>("rect");
  const [size, setSize] = useState({ width: 120, height: 80 });
  const [text, setText] = useState("");
  const [catalog, setCatalog] = useState<Catalog>();
  const [draft, setDraft] = useState<XlsxShape>();
  const load = async (last = false) => {
    const value = await editor.shapes();
    setCatalog(value);
    setDraft(
      (last
        ? value.items.at(-1)
        : value.items.find((item) => item.id === draft?.id)) ?? value.items[0],
    );
  };
  const names = {
    rect: t.rectangle,
    ellipse: t.ellipse,
    line: t.lineShape,
    textBox: t.textBox,
  };
  const stale =
    catalog?.revision !== state.document?.revision ||
    catalog?.sheet !== editor.currentState.sheet;
  let valid = true;
  if (draft) {
    try {
      checkXlsxShapeSettings(draft);
    } catch {
      valid = false;
    }
  }
  const families = new Set(
    Object.keys(controller.options.resources.profile).filter(
      (key) => !key.includes("|"),
    ),
  );
  if (draft) families.add(draft.font);
  return (
    <section aria-label={t.xlsxShapes}>
      <h3>{t.xlsxShapes}</h3>
      <p>{t.xlsxShapeHint}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            await editor.insertShape(
              kind,
              size.width,
              size.height,
              kind === "line" ? "" : text,
            );
            await load(true);
          });
        }}
      >
        <fieldset disabled={disabled}>
          <legend>{t.xlsxShapeInsert}</legend>
          <label>
            {t.objectKind}
            <select
              aria-label={t.objectKind}
              value={kind}
              onChange={(event) => {
                const next = xlsxShapeKinds.find(
                  (kind) => kind === event.currentTarget.value,
                );
                if (next) setKind(next);
              }}
            >
              {xlsxShapeKinds.map((kind) => (
                <option key={kind} value={kind}>
                  {names[kind]}
                </option>
              ))}
            </select>
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
                min={kind === "line" ? 0 : 0.1}
                max={14400}
                step="any"
                required
                value={Number.isFinite(size[key]) ? size[key] : ""}
                onChange={(event) => {
                  const value = event.currentTarget.valueAsNumber;
                  setSize((current) => ({ ...current, [key]: value }));
                }}
              />
            </label>
          ))}
          <label>
            {t.objectText}
            <textarea
              value={text}
              disabled={kind === "line"}
              maxLength={32767}
              onChange={(event) => setText(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={kind === "line" && size.width === 0 && size.height === 0}
          >
            {t.xlsxShapeInsert}
          </button>
        </fieldset>
      </form>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(() => load())}
      >
        {t.xlsxShapeLoad}
      </button>
      {catalog?.reason && <p>{catalog.reason}</p>}
      {!!catalog?.items.length && (
        <label>
          {t.xlsxShapeChoose}
          <select
            aria-label={t.xlsxShapeChoose}
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
      {draft && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setShape(draft.id, draft);
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || !!catalog?.reason}>
            <legend>{t.xlsxShapeApply}</legend>
            <label>
              {t.xlsxShapeName}
              <input
                value={draft.name}
                maxLength={255}
                required
                onChange={(event) =>
                  setDraft({ ...draft, name: event.currentTarget.value })
                }
              />
            </label>
            <label>
              {t.xlsxPictureAlt}
              <input
                value={draft.description}
                maxLength={1024}
                onChange={(event) =>
                  setDraft({ ...draft, description: event.currentTarget.value })
                }
              />
            </label>
            <label>
              {t.objectKind}
              <select
                aria-label={t.objectKind}
                value={draft.kind}
                onChange={(event) => {
                  const kind = xlsxShapeKinds.find(
                    (kind) => kind === event.currentTarget.value,
                  );
                  if (kind)
                    setDraft({
                      ...draft,
                      kind,
                      text: kind === "line" ? "" : draft.text,
                      width:
                        kind === "line"
                          ? draft.width
                          : Math.max(0.1, draft.width),
                      height:
                        kind === "line"
                          ? draft.height
                          : Math.max(0.1, draft.height),
                    });
                }}
              >
                {xlsxShapeKinds.map((kind) => (
                  <option key={kind} value={kind}>
                    {names[kind]}
                  </option>
                ))}
              </select>
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
                ["lineWidth", t.shapeLineWidth],
                ["size", t.fontSize],
              ] as const
            ).map(([key, label]) => (
              <label key={key}>
                {label}
                <input
                  type="number"
                  required
                  min={
                    key === "size"
                      ? 1
                      : (key === "width" || key === "height") &&
                          draft.kind !== "line"
                        ? 0.1
                        : 0
                  }
                  max={
                    key === "size"
                      ? 400
                      : key === "lineWidth"
                        ? 1000
                        : key === "x" || key === "y"
                          ? 1e9
                          : 14400
                  }
                  step="any"
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
                ["fill", t.shapeFill, t.noShapeFill],
                ["stroke", t.shapeStroke, t.noShapeStroke],
              ] as const
            ).map(([key, label, none]) => (
              <div key={key}>
                <label>
                  {label}
                  <input
                    type="color"
                    value={`#${draft[key] ?? "000000"}`}
                    disabled={draft[key] === null}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        [key]: event.currentTarget.value.slice(1),
                      })
                    }
                  />
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={draft[key] === null}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        [key]: event.currentTarget.checked ? null : "000000",
                      })
                    }
                  />
                  {none}
                </label>
              </div>
            ))}
            <label>
              {t.objectText}
              <textarea
                value={draft.text}
                maxLength={32767}
                disabled={draft.kind === "line"}
                onChange={(event) =>
                  setDraft({ ...draft, text: event.currentTarget.value })
                }
              />
            </label>
            <label>
              {t.fontFamily}
              <select
                aria-label={t.fontFamily}
                value={draft.font}
                onChange={(event) =>
                  setDraft({ ...draft, font: event.currentTarget.value })
                }
              >
                {[...families].map((font) => (
                  <option key={font} value={font}>
                    {font}
                  </option>
                ))}
              </select>
            </label>
            <label>
              {t.textColor}
              <input
                type="color"
                value={`#${draft.color}`}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    color: event.currentTarget.value.slice(1),
                  })
                }
              />
            </label>
            {(
              [
                ["bold", t.bold],
                ["italic", t.italic],
                ["wrap", t.wrapFrameText],
              ] as const
            ).map(([key, label]) => (
              <label key={key}>
                <input
                  type="checkbox"
                  checked={draft[key]}
                  onChange={(event) =>
                    setDraft({ ...draft, [key]: event.currentTarget.checked })
                  }
                />
                {label}
              </label>
            ))}
            <label>
              {t.xlsxTextAlignment}
              <select
                aria-label={t.xlsxTextAlignment}
                value={draft.align}
                onChange={(event) => {
                  const align = event.currentTarget.value;
                  if (
                    align === "left" ||
                    align === "center" ||
                    align === "right"
                  )
                    setDraft({ ...draft, align });
                }}
              >
                <option value="left">{t.alignLeft}</option>
                <option value="center">{t.alignCenter}</option>
                <option value="right">{t.alignRight}</option>
              </select>
            </label>
            <label>
              {t.textAnchor}
              <select
                aria-label={t.textAnchor}
                value={draft.vertical}
                onChange={(event) => {
                  const vertical = event.currentTarget.value;
                  if (
                    vertical === "top" ||
                    vertical === "center" ||
                    vertical === "bottom"
                  )
                    setDraft({ ...draft, vertical });
                }}
              >
                <option value="top">{t.alignTop}</option>
                <option value="center">{t.alignMiddle}</option>
                <option value="bottom">{t.alignBottom}</option>
              </select>
            </label>
            {(
              [
                ["left", t.textInsetLeft],
                ["top", t.textInsetTop],
                ["right", t.textInsetRight],
                ["bottom", t.textInsetBottom],
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
                  value={
                    Number.isFinite(draft.insets[key]) ? draft.insets[key] : ""
                  }
                  onChange={(event) =>
                    setDraft({
                      ...draft,
                      insets: {
                        ...draft.insets,
                        [key]: event.currentTarget.valueAsNumber,
                      },
                    })
                  }
                />
              </label>
            ))}
            <button type="submit" disabled={!valid}>
              {t.xlsxShapeApply}
            </button>
            {(
              [
                ["front", t.bringFront],
                ["back", t.sendBack],
                ["forward", t.bringForward],
                ["backward", t.sendBackward],
              ] as const
            ).map(([direction, label]) => (
              <button
                key={direction}
                type="button"
                onClick={() =>
                  controller.run(async () => {
                    await editor.editSheet({
                      action: "drawingOrder",
                      objectId: draft.id,
                      direction,
                    });
                    await load();
                  })
                }
              >
                {label}
              </button>
            ))}
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.deleteShape(draft.id);
                  await load();
                })
              }
            >
              {t.deleteObject}
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
              onClick={() => controller.run(() => editor.cutDrawing(draft.id))}
            >
              {t.cutDrawing}
            </button>
            <button
              type="button"
              onClick={() => controller.run(() => editor.copyDrawing(draft.id))}
            >
              {t.copyDrawing}
            </button>
          </fieldset>
        </form>
      )}
    </section>
  );
}
