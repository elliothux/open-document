import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxPicture,
  DocxPictures as Pictures,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxDrawingPosition } from "./docx-drawing-position.js";

export function DocxPictures({
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
  const [catalog, setCatalog] = useState<Pictures>();
  const [draft, setDraft] = useState<DocxPicture>();
  const [size, setSize] = useState({ width: 120, height: 80 });
  const load = async (known?: ReadonlySet<number>) => {
    const value = await editor.pictures();
    setCatalog(value);
    const image =
      (known && value.images.find((image) => !known.has(image.id))) ??
      value.images.find((image) => image.selected) ??
      value.images.find((image) => image.id === draft?.id) ??
      value.images[0];
    setDraft(
      image && {
        id: image.id,
        width: image.width,
        height: image.height,
        crop: [...image.crop],
      },
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
        const value = await editor.pictures();
        const image = value.images.find((image) => image.selected);
        if (active && image) {
          setCatalog(value);
          setDraft({
            id: image.id,
            width: image.width,
            height: image.height,
            crop: [...image.crop],
          });
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
  const image = catalog?.images.find((image) => image.id === draft?.id);
  const stale = catalog?.revision !== state.document?.revision;
  const apply = async (value: DocxPicture) => {
    if (!catalog) return;
    await editor.editPicture(catalog.revision, { ...value, action: "resize" });
    await load();
  };
  return (
    <section aria-label={t.pictureProperties}>
      <h3>{t.pictureProperties}</h3>
      <fieldset disabled={disabled || !editor.getSnapshot().data.selection}>
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
              onChange={(event) =>
                setSize({ ...size, [key]: event.currentTarget.valueAsNumber })
              }
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
                if (!file.size || file.size > 4194304)
                  throw new Error(t.imageInputLimit);
                const bytes = new Uint8Array(await file.arrayBuffer());
                const before = await editor.pictures();
                await editor.editPicture(before.revision, {
                  action: "insert",
                  ...size,
                  bytes,
                });
                await load(new Set(before.images.map((image) => image.id)));
              });
            }}
          />
        </label>
      </fieldset>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.loadPictures}
      </button>
      {catalog && catalog.images.length > 0 && (
        <label>
          {t.choosePicture}
          <select
            aria-label={t.choosePicture}
            disabled={disabled || stale}
            value={draft?.id ?? ""}
            onChange={(event) => {
              const image = catalog.images.find(
                (image) => image.id === Number(event.currentTarget.value),
              );
              if (image)
                setDraft({
                  id: image.id,
                  width: image.width,
                  height: image.height,
                  crop: [...image.crop],
                });
            }}
          >
            {catalog.images.map((image) => (
              <option key={image.id} value={image.id}>
                {image.name}
              </option>
            ))}
          </select>
        </label>
      )}
      {image?.reason && <p>{image.reason}</p>}
      {image && (
        <>
          <DocxDrawingPosition
            key={`${image.id}:${catalog?.revision}`}
            controller={controller}
            state={state}
            drawing={image}
            disabled={disabled || stale}
            apply={async (anchor) => {
              await editor.editPicture(catalog!.revision, {
                action: "position",
                id: image.id,
                anchor,
              });
              await load();
            }}
          />
          <label>
            {t.replacementFile}
            <input
              type="file"
              accept=".png,.jpg,.jpeg,image/png,image/jpeg"
              disabled={disabled || stale || !!image.replaceReason}
              title={image.replaceReason}
              onChange={(event) => {
                const file = event.currentTarget.files?.[0];
                event.currentTarget.value = "";
                if (!file || !catalog) return;
                controller.run(async () => {
                  if (!file.size || file.size > 4194304)
                    throw new Error(t.imageInputLimit);
                  await editor.editPicture(catalog.revision, {
                    action: "replace",
                    id: image.id,
                    bytes: new Uint8Array(await file.arrayBuffer()),
                  });
                  await load();
                });
              }}
            />
          </label>
          {image.replaceReason && image.replaceReason !== image.reason && (
            <p>{image.replaceReason}</p>
          )}
          <button
            type="button"
            disabled={disabled || stale || !!image.deleteReason}
            onClick={() =>
              controller.run(async () => {
                if (!catalog) return;
                await editor.editPicture(catalog.revision, {
                  action: "delete",
                  id: image.id,
                });
                await load();
              })
            }
          >
            {t.deletePicture}
          </button>
          {image.deleteReason && image.deleteReason !== image.reason && (
            <p>{image.deleteReason}</p>
          )}
        </>
      )}
      {draft && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() => apply(draft));
          }}
        >
          <fieldset disabled={disabled || stale || !!image?.reason}>
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
                  min={0.1}
                  max={14400}
                  step="any"
                  required
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
                      const crop: DocxPicture["crop"] = [...draft.crop];
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
                draft.crop[0] + draft.crop[2] >= 1 ||
                draft.crop[1] + draft.crop[3] >= 1
              }
            >
              {t.applyPicture}
            </button>
            <button
              type="button"
              onClick={() =>
                controller.run(
                  () =>
                    image &&
                    apply({
                      id: image.id,
                      width: image.width,
                      height: image.height,
                      crop: [0, 0, 0, 0],
                    }),
                )
              }
            >
              {t.resetCrop}
            </button>
          </fieldset>
        </form>
      )}
    </section>
  );
}
