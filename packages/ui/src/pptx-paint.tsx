import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxDash } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

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
  const [fill, setFill] = useState(`#${first?.fill ?? "336699"}`);
  const [stroke, setStroke] = useState(`#${first?.stroke ?? "000000"}`);
  const [noFill, setNoFill] = useState(first?.fill === null);
  const [noStroke, setNoStroke] = useState(first?.stroke === null);
  const [width, setWidth] = useState(String(first?.width ?? 1));
  const [dash, setDash] = useState<PptxDash>(first?.dash ?? "solid");
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
      object.appearance.stroke !== first?.stroke ||
      object.appearance.width !== first?.width ||
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
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "fill",
              color: noFill ? null : fill.slice(1),
            }),
          );
        }}
      >
        <label>
          {t.shapeFill}
          <input
            type="color"
            value={fill}
            disabled={noFill}
            onChange={(event) => setFill(event.currentTarget.value)}
          />
        </label>
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
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}
