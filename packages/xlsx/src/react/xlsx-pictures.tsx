import { useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import type { XlsxPictures as Catalog, XlsxPicture } from "../web/xlsx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function XlsxPictures({
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
  const [catalog, setCatalog] = useState<Catalog>();
  const [draft, setDraft] = useState<XlsxPicture>();
  const [size, setSize] = useState({ width: 120, height: 80 });
  const load = async (last = false) => {
    const value = await editor.pictures();
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
  return (
    <section aria-label={t.pictureProperties}>
      <h3>{t.pictureProperties}</h3>
      <p>{t.xlsxPictureHint}</p>
      <fieldset disabled={disabled}>
        <legend>{t.insertImage}</legend>
        {(
          [
            ["width", t.insertPictureWidth],
            ["height", t.insertPictureHeight],
          ] as const
        ).map(([key, label]) => (
          <label key={key}>
            {label}
            <input
              type="number"
              min={0.1}
              max={14400}
              step="any"
              value={Number.isFinite(size[key]) ? size[key] : ""}
              onChange={(event) => {
                const value = event.currentTarget.valueAsNumber;
                setSize((current) => ({ ...current, [key]: value }));
              }}
            />
          </label>
        ))}
        <label>
          {t.pictureFile}
          <input
            type="file"
            accept=".png,.jpg,.jpeg,image/png,image/jpeg"
            onChange={(event) => {
              const file = event.currentTarget.files?.[0];
              event.currentTarget.value = "";
              if (!file) return;
              controller.run(async () => {
                if (!file.size || file.size > 2097152)
                  throw new Error(t.xlsxPictureLimit);
                await editor.insertPicture(
                  new Uint8Array(await file.arrayBuffer()),
                  size.width,
                  size.height,
                  file.name,
                );
                await load(true);
              });
            }}
          />
        </label>
      </fieldset>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(() => load())}
      >
        {t.loadPictures}
      </button>
      {catalog?.reason && <p>{catalog.reason}</p>}
      {catalog && catalog.items.length > 0 && (
        <label>
          {t.choosePicture}
          <select
            aria-label={t.choosePicture}
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
              await editor.setPicture(draft.id, draft);
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || !!catalog?.reason}>
            <label>
              {t.xlsxReplacePicture}
              <input
                type="file"
                accept=".png,.jpg,.jpeg,image/png,image/jpeg"
                onChange={(event) => {
                  const file = event.currentTarget.files?.[0];
                  event.currentTarget.value = "";
                  if (!file) return;
                  controller.run(async () => {
                    const source = editor.currentState;
                    if (!file.size || file.size > 2097152)
                      throw new Error(t.xlsxPictureLimit);
                    const bytes = new Uint8Array(await file.arrayBuffer());
                    if (
                      editor.currentState.revision !== source.revision ||
                      editor.currentState.sheet !== source.sheet
                    )
                      throw new Error(t.xlsxPictureReload);
                    await editor.replacePicture(draft.id, bytes);
                    await load();
                  });
                }}
              />
            </label>
            <label>
              {t.xlsxPictureName}
              <input
                value={draft.name}
                maxLength={255}
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
              {t.xlsxPictureAnchor}
              <select
                aria-label={t.xlsxPictureAnchor}
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
                  type="number"
                  min={key === "x" || key === "y" ? 0 : 0.1}
                  max={key === "x" || key === "y" ? 1e9 : 14400}
                  step="any"
                  value={Number.isFinite(draft[key]) ? draft[key] : ""}
                  onChange={(event) => {
                    const value = event.currentTarget.valueAsNumber;
                    setDraft({
                      ...draft,
                      [key]: value,
                      ...(key === "width"
                        ? { height: (value * draft.height) / draft.width }
                        : key === "height"
                          ? { width: (value * draft.width) / draft.height }
                          : {}),
                    });
                  }}
                />
              </label>
            ))}
            {[t.cropLeft, t.cropTop, t.cropRight, t.cropBottom].map(
              (label, index) => (
                <label key={label}>
                  {label}
                  <input
                    type="number"
                    min={0}
                    max={99.999}
                    step={0.001}
                    required
                    value={
                      Number.isFinite(draft.crop[index])
                        ? draft.crop[index]! * 100
                        : ""
                    }
                    onChange={(event) => {
                      const crop = [...draft.crop];
                      crop[index] = event.currentTarget.valueAsNumber / 100;
                      setDraft({ ...draft, crop });
                    }}
                  />
                </label>
              ),
            )}
            <button
              type="submit"
              disabled={
                draft.crop[0]! + draft.crop[2]! >= 1 ||
                draft.crop[1]! + draft.crop[3]! >= 1
              }
            >
              {t.xlsxPictureApply}
            </button>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  const picture = catalog?.items.find(
                    (item) => item.id === draft.id,
                  );
                  if (!picture) return;
                  await editor.setPicture(draft.id, {
                    ...picture,
                    crop: [0, 0, 0, 0],
                  });
                  await load();
                })
              }
            >
              {t.resetCrop}
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
                  await editor.deletePicture(draft.id);
                  await load();
                })
              }
            >
              {t.deletePicture}
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
