import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxTextWatermark } from "@open-document/web/foundation";
import { imageDimensions } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

const initial: DocxTextWatermark = {
  text: "CONFIDENTIAL",
  font: "Arial",
  size: 54,
  color: "808080",
  opacity: 0.5,
  diagonal: true,
  bold: false,
  italic: false,
};
export function DocxWatermark({
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
  const [source, setSource] =
    useState<Awaited<ReturnType<DocumentEditor["watermark"]>>>();
  const [draft, setDraft] = useState(initial);
  const [kind, setKind] = useState<"text" | "picture">("text");
  const [image, setImage] = useState<string | Uint8Array>();
  const [picture, setPicture] = useState({
    width: 120,
    height: 80,
    opacity: 0.5,
  });
  const snapshot = editor.getSnapshot();
  const stale =
    source?.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision;
  const load = async () => {
    const value = await editor.watermark();
    setSource(value);
    setDraft(value.value?.kind === "text" ? value.value.value : initial);
    setKind(value.value?.kind ?? "text");
    if (value.value?.kind === "picture") {
      setImage(value.value.image);
      setPicture({
        width: value.value.width,
        height: value.value.height,
        opacity: value.value.opacity,
      });
    } else setImage(undefined);
  };
  return (
    <section aria-label={t.watermark}>
      <h4>{t.watermark}</h4>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.readTextWatermark}
      </button>
      {source && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              if (kind === "picture" && !image) return;
              await editor.setWatermark(
                kind === "picture" && image
                  ? { kind, image, ...picture }
                  : { kind: "text", value: draft },
              );
              await load();
            });
          }}
        >
          {source.reason && <p>{source.reason}</p>}
          {source.mixed && <p role="status">{t.mixedTextWatermarks}</p>}
          <fieldset disabled={disabled || stale || !!source.reason}>
            <label>
              {t.watermarkKind}
              <select
                aria-label={t.watermarkKind}
                value={kind}
                onChange={(event) =>
                  setKind(
                    event.currentTarget.value === "picture"
                      ? "picture"
                      : "text",
                  )
                }
              >
                <option value="text">{t.textWatermark}</option>
                <option value="picture">{t.pictureWatermark}</option>
              </select>
            </label>
            {kind === "picture" ? (
              <>
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
                        const before = editor.getSnapshot();
                        if (!file.size || file.size > 4194304)
                          throw new Error(t.imageInputLimit);
                        const bytes = new Uint8Array(await file.arrayBuffer());
                        const dimensions = imageDimensions(bytes);
                        const settings = await editor.pageSetup();
                        if (
                          editor.getSnapshot().documentId !==
                            before.documentId ||
                          editor.getSnapshot().revision !== before.revision
                        )
                          throw new Error(
                            "Watermark source changed while reading the image",
                          );
                        const page = settings.page;
                        if (!page || settings.reason)
                          throw new Error(
                            settings.reason || "Page setup is unavailable",
                          );
                        const naturalWidth = dimensions.width * 0.75,
                          naturalHeight = dimensions.height * 0.75;
                        const fit = Math.min(
                          1,
                          (page.width - page.left - page.right) / naturalWidth,
                          (page.height - page.top - page.bottom) /
                            naturalHeight,
                        );
                        setImage(bytes);
                        setPicture({
                          ...picture,
                          width: naturalWidth * fit,
                          height: naturalHeight * fit,
                        });
                      });
                    }}
                  />
                </label>
                {(["width", "height"] as const).map((key) => (
                  <label key={key}>
                    {key === "width" ? t.watermarkWidth : t.watermarkHeight}
                    <input
                      type="number"
                      min={0.1}
                      max={14400}
                      step="any"
                      required
                      value={picture[key]}
                      onChange={(event) =>
                        setPicture({
                          ...picture,
                          [key]: event.currentTarget.valueAsNumber,
                        })
                      }
                    />
                  </label>
                ))}
                <label>
                  {t.watermarkOpacity}
                  <input
                    type="number"
                    min={0}
                    max={100}
                    step="any"
                    required
                    value={picture.opacity * 100}
                    onChange={(event) =>
                      setPicture({
                        ...picture,
                        opacity: event.currentTarget.valueAsNumber / 100,
                      })
                    }
                  />
                </label>
              </>
            ) : (
              <>
                <label>
                  {t.watermarkText}
                  <input
                    aria-label={t.watermarkText}
                    maxLength={256}
                    required
                    value={draft.text}
                    onChange={(event) =>
                      setDraft({ ...draft, text: event.currentTarget.value })
                    }
                  />
                </label>
                <label>
                  {t.watermarkFont}
                  <input
                    aria-label={t.watermarkFont}
                    maxLength={256}
                    required
                    value={draft.font}
                    onChange={(event) =>
                      setDraft({ ...draft, font: event.currentTarget.value })
                    }
                  />
                </label>
                <label>
                  {t.watermarkSize}
                  <input
                    aria-label={t.watermarkSize}
                    type="number"
                    min={0.5}
                    max={1638}
                    step={0.5}
                    required
                    value={draft.size}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        size: event.currentTarget.valueAsNumber,
                      })
                    }
                  />
                </label>
                <label>
                  {t.watermarkColor}
                  <input
                    aria-label={t.watermarkColor}
                    type="color"
                    value={"#" + draft.color}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        color: event.currentTarget.value.slice(1),
                      })
                    }
                  />
                </label>
                <label>
                  {t.watermarkOpacity}
                  <input
                    aria-label={t.watermarkOpacity}
                    type="number"
                    min={0}
                    max={100}
                    step="any"
                    required
                    value={draft.opacity * 100}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        opacity: event.currentTarget.valueAsNumber / 100,
                      })
                    }
                  />
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={draft.diagonal}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        diagonal: event.currentTarget.checked,
                      })
                    }
                  />
                  {t.watermarkDiagonal}
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={draft.bold}
                    onChange={(event) =>
                      setDraft({ ...draft, bold: event.currentTarget.checked })
                    }
                  />
                  {t.bold}
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={draft.italic}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        italic: event.currentTarget.checked,
                      })
                    }
                  />
                  {t.italic}
                </label>
              </>
            )}
            <button type="submit" disabled={kind === "picture" && !image}>
              {t.applyTextWatermark}
            </button>
            <button
              type="button"
              disabled={!source.value && !source.mixed}
              onClick={() =>
                controller.run(async () => {
                  await editor.setWatermark(null);
                  await load();
                })
              }
            >
              {t.removeTextWatermark}
            </button>
          </fieldset>
        </form>
      )}
    </section>
  );
}
