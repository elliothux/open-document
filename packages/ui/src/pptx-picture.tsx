import { useEffect, useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function ImageInsetsForm({
  controller,
  state,
  values,
  reason,
  disabled,
  onApply,
  label,
}: {
  controller: EditorController;
  state: UiSnapshot;
  values: readonly number[];
  reason: string;
  disabled: boolean;
  onApply: (insets: [number, number, number, number]) => Promise<void>;
  label?: string;
}) {
  const t = messages(state.locale);
  const [left, top, right, bottom] = values;
  const [draft, setDraft] = useState(values.map((value) => value * 100));
  useEffect(
    () =>
      setDraft(
        [left ?? 0, top ?? 0, right ?? 0, bottom ?? 0].map(
          (value) => value * 100,
        ),
      ),
    [left, top, right, bottom],
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          onApply([
            draft[0]! / 100,
            draft[1]! / 100,
            draft[2]! / 100,
            draft[3]! / 100,
          ]),
        );
      }}
    >
      <fieldset disabled={disabled || !!reason} title={reason}>
        <legend>{label ?? t.imageInsets}</legend>
        {[
          t.imageInsetLeft,
          t.imageInsetTop,
          t.imageInsetRight,
          t.imageInsetBottom,
        ].map((label, index) => (
          <label key={label}>
            {label}
            <input
              type="number"
              min={-2147483.648}
              max={2147483.647}
              step={0.001}
              required
              value={draft[index]}
              onChange={(event) => {
                const next = event.currentTarget.valueAsNumber;
                setDraft((values) =>
                  values.map((value, i) => (i === index ? next : value)),
                );
              }}
            />
          </label>
        ))}
        <button type="button" onClick={() => setDraft([0, 0, 0, 0])}>
          {t.resetImageInsets}
        </button>
        <button type="submit">
          {t.apply} {label ?? t.imageInsets}
        </button>
      </fieldset>
    </form>
  );
}

export function PptxPicture({
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
  const object = query.objects.find((o) => o.id === query.selection.object);
  const picture = object?.picture;
  const [mode, setMode] = useState<"stretch" | "tile">(
    picture?.mode ?? "stretch",
  );
  const [opacity, setOpacity] = useState((picture?.opacity ?? 1) * 100);
  const [crop, setCrop] = useState({
    left: (picture?.left ?? 0) * 100,
    top: (picture?.top ?? 0) * 100,
    right: (picture?.right ?? 0) * 100,
    bottom: (picture?.bottom ?? 0) * 100,
  });
  const blocked =
    disabled ||
    query.selection.mode !== "object" ||
    query.selection.objects.length !== 1;
  return (
    <section aria-label={t.pictureProperties}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({ action: "imageMode", mode }),
          );
        }}
      >
        <fieldset
          disabled={blocked || !object || !!picture?.modeReason}
          title={picture?.modeReason}
        >
          <legend>{t.pictureMode}</legend>
          <label>
            {t.imageFillMode}
            <select
              value={mode}
              onChange={(event) =>
                setMode(
                  event.currentTarget.value === "tile" ? "tile" : "stretch",
                )
              }
            >
              <option value="stretch">{t.imageStretch}</option>
              <option value="tile">{t.imageTile}</option>
            </select>
          </label>
          {mode === "tile" && <p>{t.tileCropHint}</p>}
          <button type="submit">{t.applyImageFillMode}</button>
        </fieldset>
      </form>
      <fieldset disabled={blocked || !object || !!picture?.replaceReason}>
        <legend>{t.replaceImage}</legend>
        <label>
          {t.replacementFile}
          <input
            type="file"
            accept=".png,.jpg,.jpeg,image/png,image/jpeg"
            title={picture?.replaceReason}
            onChange={(event) => {
              const file = event.currentTarget.files?.[0];
              event.currentTarget.value = "";
              if (!file || !object) return;
              controller.run(async () => {
                if (!file.size || file.size > 4194304)
                  throw new Error(t.imageInputLimit);
                await editor.editObjects({
                  action: "replaceImage",
                  object: object.id,
                  bytes: new Uint8Array(await file.arrayBuffer()),
                });
              });
            }}
          />
        </label>
      </fieldset>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "imageCrop",
              left: crop.left / 100,
              top: crop.top / 100,
              right: crop.right / 100,
              bottom: crop.bottom / 100,
            }),
          );
        }}
      >
        <fieldset
          disabled={blocked || !object || !!picture?.cropReason}
          title={picture?.cropReason}
        >
          <legend>{t.pictureCrop}</legend>
          {(
            [
              ["left", t.cropLeft],
              ["top", t.cropTop],
              ["right", t.cropRight],
              ["bottom", t.cropBottom],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                required
                min={0}
                max={99.999}
                step={0.001}
                value={crop[key]}
                onChange={(event) =>
                  setCrop({ ...crop, [key]: event.currentTarget.valueAsNumber })
                }
              />
            </label>
          ))}
          <button type="submit">{t.applyCrop}</button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editObjects({
                  action: "imageCrop",
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 0,
                }),
              )
            }
          >
            {t.resetCrop}
          </button>
        </fieldset>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "imageOpacity",
              opacity: opacity / 100,
            }),
          );
        }}
      >
        <fieldset
          disabled={blocked || !object || !!picture?.opacityReason}
          title={picture?.opacityReason}
        >
          <legend>{t.pictureOpacity}</legend>
          <label>
            {t.opacityPercent}
            <input
              type="number"
              min={0}
              max={100}
              step={0.001}
              required
              value={opacity}
              onChange={(event) =>
                setOpacity(event.currentTarget.valueAsNumber)
              }
            />
          </label>
          <button type="submit">{t.applyOpacity}</button>
        </fieldset>
      </form>
    </section>
  );
}
