import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxDash, PptxCap, PptxJoin } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { PptxLineEnds } from "./pptx-line-ends.js";

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
    `#${first?.gradient?.startColor ?? first?.fill ?? "336699"}`,
  );
  const [linear, setLinear] = useState(!!first?.gradient);
  const [endColor, setEndColor] = useState(
    `#${first?.gradient?.endColor ?? "ffffff"}`,
  );
  const [angle, setAngle] = useState(String(first?.gradient?.angle ?? 0));
  const [scaled, setScaled] = useState(first?.gradient?.scaled ?? true);
  const [stroke, setStroke] = useState(`#${first?.stroke ?? "000000"}`);
  const [noFill, setNoFill] = useState(
    first?.fill === null && !first?.gradient,
  );
  const [noStroke, setNoStroke] = useState(first?.stroke === null);
  const [width, setWidth] = useState(String(first?.width ?? 1));
  const [dash, setDash] = useState<PptxDash>(first?.dash ?? "solid");
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
  const dashes = [
    ["solid", t.dashSolid],
    ["dash", t.dashRegular],
    ["dashDot", t.dashDot],
    ["dot", t.dashDotted],
    ["lgDash", t.dashLong],
    ["lgDashDot", t.dashLongDot],
    ["lgDashDotDot", t.dashLongDotDot],
    ["sysDash", t.dashSystem],
    ["sysDashDot", t.dashSystemDot],
    ["sysDashDotDot", t.dashSystemDotDot],
    ["sysDot", t.dashSystemDotted],
  ] as const;
  const reason = objects.find((object) => object.appearance.reason)?.appearance
    .reason;
  const mixed = objects.some(
    (object) =>
      object.appearance.fill !== first?.fill ||
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
          controller.run(() =>
            editor.editObjects(
              linear && !noFill
                ? {
                    action: "gradientFill",
                    startColor: fill.slice(1),
                    endColor: endColor.slice(1),
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
            value={linear ? "linear" : "solid"}
            onChange={(event) =>
              setLinear(event.currentTarget.value === "linear")
            }
          >
            <option value="solid">{t.solidColor}</option>
            <option value="linear">{t.linearGradient}</option>
          </select>
        </label>
        <label>
          {t.shapeFill}
          <input
            type="color"
            value={fill}
            disabled={noFill}
            onChange={(event) => setFill(event.currentTarget.value)}
          />
        </label>
        {linear && (
          <>
            <label>
              {t.gradientEnd}
              <input
                type="color"
                value={endColor}
                disabled={noFill}
                onChange={(event) => setEndColor(event.currentTarget.value)}
              />
            </label>
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
        <button type="submit">
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
      <fieldset disabled={!!dashReason}>
        <legend>{t.shapeLineDash}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editObjects({ action: "strokeDash", dash }),
            );
          }}
        >
          <label>
            {t.shapeLineDash}
            <select
              aria-label={t.shapeLineDash}
              value={dash}
              onChange={(event) => {
                const option = dashes.find(
                  ([value]) => value === event.currentTarget.value,
                );
                if (option) setDash(option[0]);
              }}
            >
              {dashes.map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <button type="submit">
            {t.apply} {t.shapeLineDash}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editObjects({ action: "strokeDash", dash: null }),
              )
            }
          >
            {t.resetLineDash}
          </button>
        </form>
        {dashReason && <p>{dashReason}</p>}
      </fieldset>
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
