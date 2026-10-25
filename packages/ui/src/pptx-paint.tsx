import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type {
  PptxCap,
  PptxJoin,
  PptxBackgroundFill,
} from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { PptxLineEnds } from "./pptx-line-ends.js";
import { PptxDashFields } from "./pptx-dash.js";

type Stops = Extract<PptxBackgroundFill, { kind: "linear" }>["stops"];

export function GradientStops({
  stops,
  onChange,
  state,
  disabled,
  firstLabel,
}: {
  stops: Stops;
  onChange: (stops: Stops) => void;
  state: UiSnapshot;
  disabled?: boolean;
  firstLabel: string;
}) {
  const t = messages(state.locale);
  return (
    <fieldset disabled={disabled}>
      <legend>{t.gradientStops}</legend>
      {stops.map((stop, index) => (
        <div key={index}>
          <label>
            {index === 0
              ? firstLabel
              : index === stops.length - 1
                ? t.gradientEnd
                : `${t.gradientColor} ${index + 1}`}
            <input
              type="color"
              value={`#${stop.color}`}
              onChange={(event) =>
                onChange(
                  stops.map((item, i) =>
                    i === index
                      ? { ...item, color: event.currentTarget.value.slice(1) }
                      : item,
                  ),
                )
              }
            />
          </label>
          <label>
            {t.fillOpacity} {index + 1}
            <input
              type="number"
              required
              min={0}
              max={100}
              step={0.001}
              value={Number.isFinite(stop.opacity) ? stop.opacity * 100 : ""}
              onChange={(event) =>
                onChange(
                  stops.map((item, i) =>
                    i === index
                      ? {
                          ...item,
                          opacity: event.currentTarget.valueAsNumber / 100,
                        }
                      : item,
                  ),
                )
              }
            />
          </label>
          <label>
            {t.gradientPosition} {index + 1}
            <input
              type="number"
              required
              min={(stops[index - 1]?.position ?? 0) * 100}
              max={(stops[index + 1]?.position ?? 1) * 100}
              step={0.001}
              value={Number.isFinite(stop.position) ? stop.position * 100 : ""}
              onChange={(event) =>
                onChange(
                  stops.map((item, i) =>
                    i === index
                      ? {
                          ...item,
                          position: event.currentTarget.valueAsNumber / 100,
                        }
                      : item,
                  ),
                )
              }
            />
          </label>
          <button
            type="button"
            disabled={stops.length <= 2}
            aria-label={`${t.removeGradientStop} ${index + 1}`}
            onClick={() => onChange(stops.filter((_, i) => i !== index))}
          >
            {t.removeGradientStop}
          </button>
        </div>
      ))}
      <button
        type="button"
        disabled={stops.length >= 32}
        onClick={() => {
          const last = stops[stops.length - 1]!,
            previous = stops[stops.length - 2]!;
          onChange([
            ...stops.slice(0, -1),
            {
              position: (last.position + previous.position) / 2,
              color: last.color,
              opacity: (last.opacity + previous.opacity) / 2,
            },
            last,
          ]);
        }}
      >
        {t.addGradientStop}
      </button>
    </fieldset>
  );
}

export function PptxPaint({
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
  const objects = query.objects.filter((object) =>
    query.selection.objects.includes(object.id),
  );
  const first = objects[0]?.appearance;
  const [fill, setFill] = useState(
    `#${first?.gradient?.stops[0]?.color ?? first?.fill ?? "336699"}`,
  );
  const [fillType, setFillType] = useState<
    "solid" | "linear" | "radial" | "image"
  >(first?.imageFill ? "image" : (first?.gradient?.kind ?? "solid"));
  const [imageMode, setImageMode] = useState<"stretch" | "tile">(
    first?.imageFillMode ?? "stretch",
  );
  const [stops, setStops] = useState<Stops>(
    first?.gradient?.stops ?? [
      { opacity: 1, position: 0, color: fill.slice(1) },
      { opacity: 1, position: 1, color: "ffffff" },
    ],
  );
  const [angle, setAngle] = useState(
    String(first?.gradient?.kind === "linear" ? first.gradient.angle : 0),
  );
  const [scaled, setScaled] = useState(
    first?.gradient?.kind === "linear" ? first.gradient.scaled : true,
  );
  const [stroke, setStroke] = useState(`#${first?.stroke ?? "000000"}`);
  const [noFill, setNoFill] = useState(
    first?.fill === null && !first?.gradient && !first?.imageFill,
  );
  const [noStroke, setNoStroke] = useState(first?.stroke === null);
  const [width, setWidth] = useState(String(first?.width ?? 1));
  const [cap, setCap] = useState<PptxCap>(first?.cap ?? "flat");
  const [join, setJoin] = useState<PptxJoin>(first?.join ?? "round");
  const [miter, setMiter] = useState(String(first?.miterLimit ?? 8));
  const [fillOpacity, setFillOpacity] = useState(
    String((first?.fillOpacity ?? 1) * 100),
  );
  const [strokeOpacity, setStrokeOpacity] = useState(
    String((first?.strokeOpacity ?? 1) * 100),
  );
  const penReason = objects.find((object) => object.appearance.penReason)
    ?.appearance.penReason;
  const caps = [
    ["flat", t.capFlat],
    ["rnd", t.capRound],
    ["sq", t.capSquare],
  ] as const;
  const joins = [
    ["round", t.capRound],
    ["bevel", t.joinBevel],
    ["miter", t.joinMiter],
  ] as const;
  const dashReason = objects.find((object) => object.appearance.dashReason)
    ?.appearance.dashReason;
  const reason = objects.find((object) => object.appearance.reason)?.appearance
    .reason;
  const imageReason = objects.find(
    (object) => object.appearance.imageFillReason,
  )?.appearance.imageFillReason;
  const mixed = objects.some(
    (object) =>
      object.appearance.fill !== first?.fill ||
      object.appearance.imageFill !== first?.imageFill ||
      object.appearance.imageFillMode !== first?.imageFillMode ||
      JSON.stringify(object.appearance.gradient) !==
        JSON.stringify(first?.gradient) ||
      object.appearance.stroke !== first?.stroke ||
      object.appearance.width !== first?.width ||
      object.appearance.fillOpacity !== first?.fillOpacity ||
      object.appearance.strokeOpacity !== first?.strokeOpacity ||
      object.appearance.cap !== first?.cap ||
      object.appearance.join !== first?.join ||
      object.appearance.miterLimit !== first?.miterLimit ||
      object.appearance.dash !== first?.dash,
  );
  return (
    <fieldset
      disabled={
        disabled ||
        objects.length === 0 ||
        query.selection.mode !== "object" ||
        !!reason
      }
    >
      <legend>{t.shapeAppearance}</legend>
      {mixed && <p>{t.mixed}</p>}
      {([false, true] as const).map((border) => {
        const label = border ? t.strokeOpacity : t.fillOpacity;
        const opacityReason = objects.find((object) =>
          border
            ? object.appearance.strokeOpacityReason
            : object.appearance.fillOpacityReason,
        )?.appearance;
        const message = border
          ? opacityReason?.strokeOpacityReason
          : opacityReason?.fillOpacityReason;
        return (
          <form
            key={label}
            onSubmit={(event) => {
              event.preventDefault();
              controller.run(() =>
                editor.editObjects({
                  action: border ? "strokeOpacity" : "fillOpacity",
                  opacity: Number(border ? strokeOpacity : fillOpacity) / 100,
                }),
              );
            }}
          >
            <label>
              {label}
              <input
                type="number"
                min={0}
                max={100}
                step="any"
                required
                disabled={!!message}
                value={border ? strokeOpacity : fillOpacity}
                onChange={(event) =>
                  (border ? setStrokeOpacity : setFillOpacity)(
                    event.currentTarget.value,
                  )
                }
              />
            </label>
            <button type="submit" disabled={!!message}>
              {t.apply} {label}
            </button>
            {message && <p>{message}</p>}
          </form>
        );
      })}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (fillType === "image" && !noFill) return;
          controller.run(() =>
            editor.editObjects(
              fillType === "radial" && !noFill
                ? { action: "radialGradientFill", stops }
                : fillType === "linear" && !noFill
                  ? {
                      action: "gradientFill",
                      stops,
                      angle: Number(angle),
                      scaled,
                    }
                  : {
                      action: "fill",
                      color: noFill ? null : fill.slice(1),
                    },
            ),
          );
        }}
      >
        <label>
          {t.shapeFillType}
          <select
            aria-label={t.shapeFillType}
            value={fillType}
            onChange={(event) => {
              if (event.currentTarget.value === "image") setNoFill(false);
              if (
                ["linear", "radial"].includes(event.currentTarget.value) &&
                fillType === "solid"
              )
                setStops(
                  stops.map((stop, index) =>
                    index === 0 ? { ...stop, color: fill.slice(1) } : stop,
                  ),
                );
              setFillType(
                event.currentTarget.value === "image"
                  ? "image"
                  : event.currentTarget.value === "linear"
                    ? "linear"
                    : event.currentTarget.value === "radial"
                      ? "radial"
                      : "solid",
              );
            }}
          >
            <option value="solid">{t.solidColor}</option>
            <option value="linear">{t.linearGradient}</option>
            <option value="radial">{t.radialGradient}</option>
            <option value="image" disabled={!!imageReason}>
              {t.imageFill}
            </option>
          </select>
        </label>
        {fillType === "image" && !noFill && (
          <>
            <label>
              {t.imageFillMode}
              <select
                aria-label={t.imageFillMode}
                value={imageMode}
                disabled={!!imageReason}
                onChange={(event) =>
                  setImageMode(
                    event.currentTarget.value === "tile" ? "tile" : "stretch",
                  )
                }
              >
                <option value="stretch">{t.imageStretch}</option>
                <option value="tile">{t.imageTile}</option>
              </select>
            </label>
            <button
              type="button"
              disabled={
                !!imageReason ||
                objects.some((object) => !object.appearance.imageFill)
              }
              onClick={() =>
                controller.run(() =>
                  editor.editObjects({
                    action: "imageFillMode",
                    mode: imageMode,
                  }),
                )
              }
            >
              {t.applyImageFillMode}
            </button>
            <label>
              {t.shapeFillImage}
              <input
                type="file"
                accept=".png,.jpg,.jpeg,image/png,image/jpeg"
                disabled={!!imageReason}
                onChange={(event) => {
                  const file = event.currentTarget.files?.[0];
                  event.currentTarget.value = "";
                  if (!file) return;
                  const targets = [...query.selection.objects];
                  const mode = imageMode;
                  controller.run(async () => {
                    if (!file.size || file.size > 4194304)
                      throw new Error(t.imageInputLimit);
                    await editor.editObjects({
                      action: "imageFill",
                      objects: targets,
                      bytes: new Uint8Array(await file.arrayBuffer()),
                      mode,
                    });
                  });
                }}
              />
              {imageReason && <p>{imageReason}</p>}
            </label>
          </>
        )}
        {(fillType === "solid" || fillType === "image") && (
          <label>
            {t.shapeFill}
            <input
              type="color"
              value={fill}
              disabled={noFill || fillType === "image"}
              onChange={(event) => setFill(event.currentTarget.value)}
            />
          </label>
        )}
        {(fillType === "linear" || fillType === "radial") && (
          <GradientStops
            stops={stops}
            onChange={setStops}
            state={state}
            disabled={noFill}
            firstLabel={t.shapeFill}
          />
        )}
        {fillType === "linear" && (
          <>
            <label>
              {t.gradientAngle}
              <input
                type="number"
                min={0}
                max={360}
                step="any"
                required
                disabled={noFill}
                value={angle}
                onChange={(event) => setAngle(event.currentTarget.value)}
              />
            </label>
            <label>
              <input
                type="checkbox"
                checked={scaled}
                disabled={noFill}
                onChange={(event) => setScaled(event.currentTarget.checked)}
              />
              {t.shapeGradientScaled}
            </label>
          </>
        )}
        <label>
          <input
            type="checkbox"
            checked={noFill}
            onChange={(event) => setNoFill(event.currentTarget.checked)}
          />
          {t.noShapeFill}
        </label>
        <button type="submit" disabled={fillType === "image" && !noFill}>
          {t.apply} {t.shapeFill}
        </button>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "stroke",
              color: noStroke ? null : stroke.slice(1),
              width: Number(width),
            }),
          );
        }}
      >
        <label>
          {t.shapeStroke}
          <input
            type="color"
            value={stroke}
            disabled={noStroke}
            onChange={(event) => setStroke(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.shapeLineWidth}
          <input
            type="number"
            min={0.1}
            max={1000}
            step="any"
            required
            value={width}
            onChange={(event) => setWidth(event.currentTarget.value)}
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={noStroke}
            onChange={(event) => setNoStroke(event.currentTarget.checked)}
          />
          {t.noShapeStroke}
        </label>
        <button type="submit">
          {t.apply} {t.shapeStroke}
        </button>
      </form>
      <PptxDashFields
        controller={controller}
        state={state}
        editor={editor}
        value={first?.dash ?? "solid"}
        reason={dashReason ?? ""}
      />
      <fieldset disabled={!!penReason}>
        <legend>{t.shapeLinePen}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editObjects({ action: "strokeCap", cap }),
            );
          }}
        >
          <label>
            {t.shapeLineCap}
            <select
              aria-label={t.shapeLineCap}
              value={cap}
              onChange={(event) => {
                const option = caps.find(
                  ([value]) => value === event.currentTarget.value,
                );
                if (option) setCap(option[0]);
              }}
            >
              {caps.map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <button type="submit">
            {t.apply} {t.shapeLineCap}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editObjects({ action: "strokeCap", cap: null }),
              )
            }
          >
            {t.resetLineCap}
          </button>
        </form>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editObjects(
                join === "miter"
                  ? { action: "strokeJoin", join, miterLimit: Number(miter) }
                  : { action: "strokeJoin", join },
              ),
            );
          }}
        >
          <label>
            {t.shapeLineJoin}
            <select
              aria-label={t.shapeLineJoin}
              value={join}
              onChange={(event) => {
                const option = joins.find(
                  ([value]) => value === event.currentTarget.value,
                );
                if (option) setJoin(option[0]);
              }}
            >
              {joins.map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t.lineMiterLimit}
            <input
              type="number"
              required
              min={1}
              max={1000}
              step="any"
              disabled={join !== "miter"}
              value={miter}
              onChange={(event) => setMiter(event.currentTarget.value)}
            />
          </label>
          <button type="submit">
            {t.apply} {t.shapeLineJoin}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editObjects({ action: "strokeJoin", join: null }),
              )
            }
          >
            {t.resetLineJoin}
          </button>
        </form>
        {penReason && <p>{penReason}</p>}
      </fieldset>
      <PptxLineEnds
        key={JSON.stringify(
          objects.map((o) => [
            o.id,
            o.appearance.headEnd,
            o.appearance.tailEnd,
          ]),
        )}
        editor={editor}
        controller={controller}
        state={state}
        disabled={disabled}
      />
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}
