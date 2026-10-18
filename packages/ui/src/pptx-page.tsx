import { useState } from "react";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";
import { ImageInsetsForm } from "./pptx-picture.js";
import { GradientStops } from "./pptx-paint.js";
import type { PptxBackgroundFill } from "@open-document/web/pptx";

export function PptxSlideLayout({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const layout =
    file.format === "pptx" ? file.editor.query.slideLayout : undefined;
  const [chosen, setChosen] = useState(layout?.current ?? "");
  if (file.format !== "pptx" || !layout) return null;
  const editor = file.editor,
    t = messages(state.locale);
  const masters = [...new Set(layout.choices.map((choice) => choice.master))];
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSlides({ action: "layout", id: chosen }),
        );
      }}
    >
      <fieldset disabled={disabled || !!layout.reason}>
        <legend>{t.slideLayout}</legend>
        <label>
          {t.chooseSlideLayout}
          <select
            aria-label={t.chooseSlideLayout}
            value={chosen}
            onChange={(event) => setChosen(event.currentTarget.value)}
          >
            {layout.choices.map((choice, index) => (
              <option key={choice.id} value={choice.id}>
                {choice.name || `${t.slideLayout} ${index + 1}`} /{" "}
                {choice.masterName ||
                  `${t.slideMaster} ${masters.indexOf(choice.master) + 1}`}
              </option>
            ))}
          </select>
        </label>
        <button type="submit" disabled={!chosen || chosen === layout.current}>
          {t.applySlideLayout}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(() => editor.editSlides({ action: "resetLayout" }))
          }
        >
          {t.resetSlideLayout}
        </button>
      </fieldset>
      {layout.reason && <p>{layout.reason}</p>}
    </form>
  );
}

export function PptxNotes({ controller, state, file, disabled }: PanelProps) {
  const notes = file.format === "pptx" ? file.editor.query.notes : undefined;
  const [text, setText] = useState(notes?.text ?? "");
  if (file.format !== "pptx" || !notes) return null;
  const editor = file.editor,
    t = messages(state.locale);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() => editor.editSlides({ action: "notes", text }));
      }}
    >
      <fieldset disabled={disabled || !!notes.reason}>
        <legend>{t.speakerNotes}</legend>
        <label>
          {t.speakerNotes}
          <textarea
            aria-label={t.speakerNotes}
            maxLength={32767}
            value={text}
            onChange={(e) => setText(e.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={text === notes.text}>
          {t.applyNotes}
        </button>
        <button
          type="button"
          disabled={!notes.text}
          onClick={() =>
            controller.run(() =>
              editor.editSlides({ action: "notes", text: "" }),
            )
          }
        >
          {t.clearNotes}
        </button>
      </fieldset>
      {notes.reason && <p>{notes.reason}</p>}
    </form>
  );
}

export function PptxBackground({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const t = messages(state.locale);
  const background =
    file.format === "pptx" ? file.editor.query.background : undefined;
  const fill = background?.value;
  const [kind, setKind] = useState<"solid" | "linear" | "image">(
    fill?.kind ?? "solid",
  );
  const [mode, setMode] = useState<"stretch" | "tile">(
    fill?.kind === "image" ? fill.mode : "stretch",
  );
  const [opacity, setOpacity] = useState(
    (fill?.kind === "image" ? fill.opacity : 1) * 100,
  );
  const [crop, setCrop] = useState({
    left: (fill?.kind === "image" ? fill.crop[0] : 0) * 100,
    top: (fill?.kind === "image" ? fill.crop[1] : 0) * 100,
    right: (fill?.kind === "image" ? fill.crop[2] : 0) * 100,
    bottom: (fill?.kind === "image" ? fill.crop[3] : 0) * 100,
  });
  const [color, setColor] = useState(
    `#${fill?.kind === "solid" ? fill.color : fill?.kind === "linear" ? fill.stops[0]?.color : "ffffff"}`,
  );
  const [stops, setStops] = useState<
    Extract<PptxBackgroundFill, { kind: "linear" }>["stops"]
  >(
    fill?.kind === "linear"
      ? fill.stops
      : [
          { position: 0, color: color.slice(1) },
          { position: 1, color: "000000" },
        ],
  );
  const [angle, setAngle] = useState(
    fill?.kind === "linear" ? String(fill.angle) : "0",
  );
  const [scaled, setScaled] = useState(
    fill?.kind === "linear" ? fill.scaled : true,
  );
  if (file.format !== "pptx" || !background) return null;
  const editor = file.editor;
  return (
    <>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (kind === "image") {
            controller.run(() =>
              editor.editSlides({
                action: "backgroundImageFormat",
                mode,
                crop: [
                  crop.left / 100,
                  crop.top / 100,
                  crop.right / 100,
                  crop.bottom / 100,
                ],
                opacity: opacity / 100,
              }),
            );
            return;
          }
          controller.run(() =>
            editor.editSlides({
              action: "background",
              value:
                kind === "solid"
                  ? { kind, color: color.slice(1) }
                  : {
                      kind,
                      stops,
                      angle: Number(angle),
                      scaled,
                    },
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !!background.reason}>
          <legend>{t.slideBackground}</legend>
          <label>
            {t.backgroundType}
            <select
              value={kind}
              onChange={(event) => {
                const value = event.currentTarget.value;
                if (value === "linear" && kind === "solid")
                  setStops(
                    stops.map((stop, index) =>
                      index === 0 ? { ...stop, color: color.slice(1) } : stop,
                    ),
                  );
                if (
                  value === "solid" ||
                  value === "linear" ||
                  value === "image"
                )
                  setKind(value);
              }}
            >
              <option value="solid">{t.solidColor}</option>
              <option value="linear">{t.linearGradient}</option>
              <option value="image">{t.imageFill}</option>
            </select>
          </label>
          {kind === "image" && (
            <>
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
              <fieldset disabled={fill?.kind !== "image"}>
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
                        setCrop({
                          ...crop,
                          [key]: event.currentTarget.valueAsNumber,
                        })
                      }
                    />
                  </label>
                ))}
                <button
                  type="button"
                  onClick={() =>
                    setCrop({ left: 0, top: 0, right: 0, bottom: 0 })
                  }
                >
                  {t.resetCrop}
                </button>
              </fieldset>
              {mode === "tile" && <p>{t.tileCropHint}</p>}
              <label>
                {t.opacityPercent}
                <input
                  type="number"
                  required
                  min={0}
                  max={100}
                  step={0.001}
                  value={opacity}
                  onChange={(event) =>
                    setOpacity(event.currentTarget.valueAsNumber)
                  }
                  disabled={fill?.kind !== "image"}
                />
              </label>
              <label>
                {t.slideBackgroundPicture}
                <input
                  type="file"
                  accept=".png,.jpg,.jpeg,image/png,image/jpeg"
                  onChange={(event) => {
                    const input = event.currentTarget.files?.[0];
                    event.currentTarget.value = "";
                    if (!input) return;
                    const slide = editor.query.slide;
                    controller.run(async () => {
                      if (!input.size || input.size > 4194304)
                        throw new Error(t.imageInputLimit);
                      const bytes = new Uint8Array(await input.arrayBuffer());
                      if (editor.query.slide !== slide)
                        throw new Error(t.backgroundImageTargetChanged);
                      await editor.editSlides(
                        { action: "backgroundImage", bytes, mode },
                        slide,
                      );
                    });
                  }}
                />
              </label>
            </>
          )}
          {kind === "solid" && (
            <label>
              {t.slideBackground}
              <input
                type="color"
                value={color}
                onChange={(event) => setColor(event.currentTarget.value)}
              />
            </label>
          )}
          {kind === "linear" && (
            <>
              <GradientStops
                stops={stops}
                onChange={setStops}
                state={state}
                firstLabel={t.gradientStart}
              />
              <label>
                {t.gradientAngle}
                <input
                  type="number"
                  required
                  min={0}
                  max={360}
                  step="any"
                  value={angle}
                  onChange={(event) => setAngle(event.currentTarget.value)}
                />
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={scaled}
                  onChange={(event) => setScaled(event.currentTarget.checked)}
                />
                {t.gradientScaled}
              </label>
            </>
          )}
          <button
            type="submit"
            disabled={kind === "image" && fill?.kind !== "image"}
            onMouseDown={(event) => event.preventDefault()}
            aria-label={`${t.apply} ${t.slideBackground}`}
          >
            {t.apply}
          </button>
          <button
            type="button"
            disabled={!background.explicit}
            onMouseDown={(event) => event.preventDefault()}
            onClick={() =>
              controller.run(() =>
                editor.editSlides({ action: "background", value: null }),
              )
            }
          >
            {t.inheritStyleProperty}
          </button>
        </fieldset>
        {background.reason && <p>{background.reason}</p>}
      </form>
      {fill?.kind === "image" && (
        <ImageInsetsForm
          label={`${t.slideBackground}: ${t.imageInsets}`}
          controller={controller}
          state={state}
          values={fill.insets}
          reason={background.reason}
          disabled={disabled || fill.mode !== "stretch"}
          onApply={(insets) =>
            editor.editSlides({ action: "backgroundImageInsets", insets })
          }
        />
      )}
    </>
  );
}

export function PptxSize({ controller, state, file, disabled }: PanelProps) {
  const [width, setWidth] = useState(
    file.format === "pptx" ? String(file.editor.query.width) : "",
  );
  const [height, setHeight] = useState(
    file.format === "pptx" ? String(file.editor.query.height) : "",
  );
  if (file.format !== "pptx") return null;
  const editor = file.editor,
    t = messages(state.locale);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSlides({
            action: "size",
            width: Number(width),
            height: Number(height),
          }),
        );
      }}
    >
      <fieldset disabled={disabled || !!editor.query.slideSizeReason}>
        <legend>{t.slideSize}</legend>
        <p>{t.scaleSlideContents}</p>
        <label>
          {t.pageWidth}
          <input
            type="number"
            min="1"
            max="14400"
            step="any"
            required
            value={width}
            onChange={(event) => setWidth(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.pageHeight}
          <input
            type="number"
            min="1"
            max="14400"
            step="any"
            required
            value={height}
            onChange={(event) => setHeight(event.currentTarget.value)}
          />
        </label>
        <button
          type="button"
          onClick={() => {
            setWidth("960");
            setHeight("540");
          }}
        >
          16:9
        </button>
        <button
          type="button"
          onClick={() => {
            setWidth("720");
            setHeight("540");
          }}
        >
          4:3
        </button>
        <button type="submit" aria-label={`${t.apply} ${t.slideSize}`}>
          {t.apply}
        </button>
      </fieldset>
      {editor.query.slideSizeReason && <p>{editor.query.slideSizeReason}</p>}
    </form>
  );
}
