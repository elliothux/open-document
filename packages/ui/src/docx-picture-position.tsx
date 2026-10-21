import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxPictures,
  DrawingAnchor,
  DrawingAxis,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxPicturePosition({
  controller,
  state,
  editor,
  image,
  revision,
  disabled,
  applied,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  image: DocxPictures["images"][number];
  revision: number;
  disabled: boolean;
  applied: () => Promise<void>;
}) {
  const t = messages(state.locale);
  const [anchor, setAnchor] = useState<DrawingAnchor | null>(image.anchor);
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
        controller.run(async () => {
          await editor.editPicture(revision, {
            action: "position",
            id: image.id,
            anchor,
          });
          await applied();
        });
      }}
    >
      <fieldset disabled={disabled || !!image.positionReason}>
        <legend>{t.picturePosition}</legend>
        <label>
          {t.picturePlacement}
          <select
            aria-label={t.picturePlacement}
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
            <option value="inline">{t.pictureInline}</option>
            <option value="front">{t.pictureInFront}</option>
            <option value="behind">{t.pictureBehind}</option>
            <option value="topBottom">{t.pictureTopBottom}</option>
            <option value="square">{t.pictureSquare}</option>
          </select>
        </label>
        {anchor && (
          <>
            {anchor.wrapping === "square" && (
              <label>
                {t.pictureWrapSide}
                <select
                  aria-label={t.pictureWrapSide}
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
                  <option value="bothSides">{t.pictureWrapBoth}</option>
                  <option value="left">{t.pictureWrapLeft}</option>
                  <option value="right">{t.pictureWrapRight}</option>
                  <option value="largest">{t.pictureWrapLargest}</option>
                </select>
              </label>
            )}
            {(["top", "right", "bottom", "left"] as const).map((key) => (
              <label key={key}>
                {key === "top"
                  ? t.pictureDistanceTop
                  : key === "right"
                    ? t.pictureDistanceRight
                    : key === "bottom"
                      ? t.pictureDistanceBottom
                      : t.pictureDistanceLeft}
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
                ? t.pictureHorizontalReference
                : t.pictureVerticalReference;
              const placementLabel = horizontal
                ? t.pictureHorizontalPlacement
                : t.pictureVerticalPlacement;
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
                      <option value="page">{t.picturePageReference}</option>
                      <option value="margin">{t.pictureMarginReference}</option>
                      <option value={horizontal ? "column" : "paragraph"}>
                        {horizontal
                          ? t.pictureColumnReference
                          : t.pictureParagraphReference}
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
                      <option value="offset">{t.pictureOffset}</option>
                      {alignments.map((value) => (
                        <option key={value} value={value}>
                          {value === "center"
                            ? t.alignCenter
                            : value === "left"
                              ? t.alignLeft
                              : value === "right"
                                ? t.alignRight
                                : value === "top"
                                  ? t.pictureAlignTop
                                  : t.pictureAlignBottom}
                        </option>
                      ))}
                    </select>
                  </label>
                  {axis.offset !== null && (
                    <label>
                      {horizontal
                        ? t.pictureHorizontalOffset
                        : t.pictureVerticalOffset}
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
              {t.pictureLayerOrder}
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
        <button type="submit">{t.applyPicturePosition}</button>
      </fieldset>
      {image.positionReason && <p>{image.positionReason}</p>}
    </form>
  );
}
