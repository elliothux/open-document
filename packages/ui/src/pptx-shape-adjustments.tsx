import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxShapeAdjustments({
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
  const objects = query.objects.filter((o) =>
    query.selection.objects.includes(o.id),
  );
  const first = objects[0]?.shapeAdjustments;
  const [draft, setDraft] = useState<Record<string, string>>(
    Object.fromEntries(
      first?.values.map((v) => [v.name, String(v.value * 100)]) ?? [],
    ),
  );
  if (!first?.values.length) return null;
  const reason = objects.find((o) => o.shapeAdjustments.reason)
    ?.shapeAdjustments.reason;
  const compatible = objects.every(
    (o) =>
      (o.shapeAdjustments.preset === first.preset ||
        !first.values.some((v) => v.name === "adj")) &&
      o.shapeAdjustments.values.map((v) => v.name).join() ===
        first.values.map((v) => v.name).join(),
  );
  return (
    <fieldset
      disabled={
        disabled || query.selection.mode !== "object" || !!reason || !compatible
      }
    >
      <legend>{t.shapeAdjustments}</legend>
      {first.values.map((guide) => {
        const label = ["bentConnector5", "curvedConnector5"].includes(
          first.preset,
        )
          ? guide.name === "adj1"
            ? t.connectorFirstHorizontalBend
            : guide.name === "adj2"
              ? t.connectorVerticalBend
              : t.connectorSecondHorizontalBend
          : ["bentConnector4", "curvedConnector4"].includes(first.preset)
            ? guide.name === "adj1"
              ? t.connectorHorizontalBend
              : t.connectorVerticalBend
            : guide.name === "adj"
              ? first.preset === "roundRect"
                ? t.cornerRadius
                : first.preset === "triangle"
                  ? t.triangleApex
                  : ["chevron", "homePlate"].includes(first.preset)
                    ? t.arrowHead
                    : first.preset === "hexagon"
                      ? t.shapeSideInset
                      : first.preset === "octagon"
                        ? t.shapeCornerCut
                        : first.preset === "plus"
                          ? t.shapeArmInset
                          : [
                                "star4",
                                "star5",
                                "star6",
                                "star8",
                                "star10",
                                "star12",
                              ].includes(first.preset)
                            ? t.shapeInnerRadius
                            : t.shapeSlant
              : guide.name === "adj1"
                ? ["bentConnector3", "curvedConnector3"].includes(first.preset)
                  ? t.connectorBend
                  : t.arrowShaft
                : ["quadArrow", "leftRightUpArrow"].includes(first.preset) &&
                    guide.name === "adj2"
                  ? t.arrowHeadWidth
                  : t.arrowHead;
        const mixed = objects.some(
          (o) =>
            o.shapeAdjustments.values.find((v) => v.name === guide.name)
              ?.value !== guide.value,
        );
        const maximum = Math.min(
          ...objects.map(
            (o) =>
              o.shapeAdjustments.values.find((v) => v.name === guide.name)
                ?.maximum ?? 0,
          ),
        );
        return (
          <form
            key={guide.name}
            onSubmit={(event) => {
              event.preventDefault();
              controller.run(() =>
                editor.editObjects({
                  action: "shapeAdjustment",
                  name: guide.name,
                  value: Number(draft[guide.name]) / 100,
                }),
              );
            }}
          >
            <label>
              {label}
              <input
                type="number"
                required
                min={0}
                max={maximum * 100}
                step="any"
                value={draft[guide.name] ?? ""}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    [guide.name]: event.currentTarget.value,
                  })
                }
              />
            </label>
            {mixed && <p>{t.mixed}</p>}
            <button type="submit">
              {t.apply} {label}
            </button>
            <button
              type="button"
              aria-label={`${t.resetShapeAdjustment}: ${label}`}
              onClick={() =>
                controller.run(() =>
                  editor.editObjects({
                    action: "shapeAdjustment",
                    name: guide.name,
                    value: null,
                  }),
                )
              }
            >
              {t.resetShapeAdjustment}
            </button>
          </form>
        );
      })}
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}
