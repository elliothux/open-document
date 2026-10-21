import { useState } from "react";
import type { DrawingAnchor, DrawingAxis } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxDrawingPosition({
  controller,
  state,
  drawing,
  disabled,
  apply,
}: {
  controller: EditorController;
  state: UiSnapshot;
  drawing: { anchor: DrawingAnchor | null; positionReason: string };
  disabled: boolean;
  apply: (anchor: DrawingAnchor | null) => Promise<void>;
}) {
  const t = messages(state.locale);
  const [anchor, setAnchor] = useState<DrawingAnchor | null>(drawing.anchor);
  const defaults: DrawingAnchor = {
    horizontal: { relativeTo: "page", offset: 0, align: null },
    vertical: { relativeTo: "paragraph", offset: 0, align: null },
    behind: false,
    order: 0,
    wrapping: "none",
    wrapSide: "bothSides",
    distance: { top: 0, right: 0, bottom: 0, left: 0 },
  };
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() => apply(anchor));
      }}
    >
      <fieldset disabled={disabled || !!drawing.positionReason}>
        <legend>{t.drawingPosition}</legend>
        <label>
          {t.drawingPlacement}
          <select
            aria-label={t.drawingPlacement}
            value={
              anchor === null
                ? "inline"
                : anchor.wrapping === "topBottom"
                  ? "topBottom"
                  : anchor.wrapping === "square"
                    ? "square"
                    : anchor.behind
                      ? "behind"
                      : "front"
            }
            onChange={(event) => {
              const value = event.currentTarget.value;
              setAnchor(
                value === "inline"
                  ? null
                  : {
                      ...(anchor ?? defaults),
                      behind: value === "behind",
                      wrapping:
                        value === "topBottom"
                          ? "topBottom"
                          : value === "square"
                            ? "square"
                            : "none",
                      wrapSide:
                        value === "square"
                          ? (anchor?.wrapSide ?? "bothSides")
                          : "bothSides",
                    },
              );
            }}
          >
            <option value="inline">{t.drawingInline}</option>
            <option value="front">{t.drawingInFront}</option>
            <option value="behind">{t.drawingBehind}</option>
            <option value="topBottom">{t.drawingTopBottom}</option>
            <option value="square">{t.drawingSquare}</option>
          </select>
        </label>
        {anchor && (
          <>
            {anchor.wrapping === "square" && (
              <label>
                {t.drawingWrapSide}
                <select
                  aria-label={t.drawingWrapSide}
                  value={anchor.wrapSide}
                  onChange={(event) => {
                    const value = event.currentTarget.value;
                    if (
                      value === "bothSides" ||
                      value === "left" ||
                      value === "right" ||
                      value === "largest"
                    )
                      setAnchor({ ...anchor, wrapSide: value });
                  }}
                >
                  <option value="bothSides">{t.drawingWrapBoth}</option>
                  <option value="left">{t.drawingWrapLeft}</option>
                  <option value="right">{t.drawingWrapRight}</option>
                  <option value="largest">{t.drawingWrapLargest}</option>
                </select>
              </label>
            )}
            {(["top", "right", "bottom", "left"] as const).map((key) => (
              <label key={key}>
                {key === "top"
                  ? t.drawingDistanceTop
                  : key === "right"
                    ? t.drawingDistanceRight
                    : key === "bottom"
                      ? t.drawingDistanceBottom
                      : t.drawingDistanceLeft}
                <input
                  type="number"
                  min={0}
                  max={14400}
                  step="any"
                  required
                  value={
                    Number.isFinite(anchor.distance[key])
                      ? anchor.distance[key]
                      : ""
                  }
                  onChange={(event) =>
                    setAnchor({
                      ...anchor,
                      distance: {
                        ...anchor.distance,
                        [key]: event.currentTarget.valueAsNumber,
                      },
                    })
                  }
                />
              </label>
            ))}
            {(["horizontal", "vertical"] as const).map((key) => {
              const axis = anchor[key];
              const horizontal = key === "horizontal";
              const update = (value: DrawingAxis) =>
                setAnchor({ ...anchor, [key]: value });
              const referenceLabel = horizontal
                ? t.drawingHorizontalReference
                : t.drawingVerticalReference;
              const placementLabel = horizontal
                ? t.drawingHorizontalPlacement
                : t.drawingVerticalPlacement;
              const alignments = horizontal
                ? ["left", "center", "right"]
                : ["top", "center", "bottom"];
              return (
                <div key={key}>
                  <label>
                    {referenceLabel}
                    <select
                      aria-label={referenceLabel}
                      value={axis.relativeTo}
                      onChange={(event) =>
                        update({
                          ...axis,
                          relativeTo: event.currentTarget.value,
                        })
                      }
                    >
                      <option value="page">{t.drawingPageReference}</option>
                      <option value="margin">{t.drawingMarginReference}</option>
                      <option value={horizontal ? "column" : "paragraph"}>
                        {horizontal
                          ? t.drawingColumnReference
                          : t.drawingParagraphReference}
                      </option>
                    </select>
                  </label>
                  <label>
                    {placementLabel}
                    <select
                      aria-label={placementLabel}
                      value={axis.align ?? "offset"}
                      onChange={(event) => {
                        const value = event.currentTarget.value;
                        update(
                          value === "offset"
                            ? {
                                relativeTo: axis.relativeTo,
                                offset: 0,
                                align: null,
                              }
                            : {
                                relativeTo: axis.relativeTo,
                                offset: null,
                                align: value,
                              },
                        );
                      }}
                    >
                      <option value="offset">{t.drawingOffset}</option>
                      {alignments.map((value) => (
                        <option key={value} value={value}>
                          {value === "center"
                            ? t.alignCenter
                            : value === "left"
                              ? t.alignLeft
                              : value === "right"
                                ? t.alignRight
                                : value === "top"
                                  ? t.drawingAlignTop
                                  : t.drawingAlignBottom}
                        </option>
                      ))}
                    </select>
                  </label>
                  {axis.offset !== null && (
                    <label>
                      {horizontal
                        ? t.drawingHorizontalOffset
                        : t.drawingVerticalOffset}
                      <input
                        type="number"
                        min={-14400}
                        max={14400}
                        step="any"
                        required
                        value={Number.isFinite(axis.offset) ? axis.offset : ""}
                        onChange={(event) =>
                          update({
                            relativeTo: axis.relativeTo,
                            align: null,
                            offset: event.currentTarget.valueAsNumber,
                          })
                        }
                      />
                    </label>
                  )}
                </div>
              );
            })}
            <label>
              {t.drawingLayerOrder}
              <input
                type="number"
                min={0}
                max={4294967295}
                step={1}
                required
                value={Number.isFinite(anchor.order) ? anchor.order : ""}
                onChange={(event) =>
                  setAnchor({
                    ...anchor,
                    order: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
          </>
        )}
        <button type="submit">{t.applyDrawingPosition}</button>
      </fieldset>
      {drawing.positionReason && <p>{drawing.positionReason}</p>}
    </form>
  );
}
