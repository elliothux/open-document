import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxTextFrame({
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
  const first = objects[0]?.textFrame;
  const [anchor, setAnchor] = useState(first?.anchor ?? "t");
  const [wrap, setWrap] = useState(first?.wrap ?? true);
  const [fit, setFit] = useState(first?.fit ?? "none");
  const [columns, setColumns] = useState(String(first?.columns ?? 1));
  const [gap, setGap] = useState(String(first?.columnGap ?? 0));
  const [rtl, setRtl] = useState(first?.rtlColumns ?? false);
  const [direction, setDirection] = useState(first?.direction ?? "horz");
  const [rotation, setRotation] = useState(String(first?.rotation ?? 0));
  const [margins, setMargins] = useState({
    left: String(first?.left ?? 7.2),
    top: String(first?.top ?? 3.6),
    right: String(first?.right ?? 7.2),
    bottom: String(first?.bottom ?? 3.6),
  });
  const reason = objects.find((object) => object.textFrame.reason)?.textFrame
    .reason;
  const mixed = objects.some((object) =>
    (
      [
        "left",
        "top",
        "right",
        "bottom",
        "anchor",
        "wrap",
        "fit",
        "columns",
        "columnGap",
        "rtlColumns",
        "direction",
        "rotation",
      ] as const
    ).some((key) => object.textFrame[key] !== first?.[key]),
  );
  return (
    <fieldset disabled={disabled || objects.length === 0 || !!reason}>
      <legend>{t.textFrame}</legend>
      <label>
        {t.textDirection}
        <select
          aria-label={t.textDirection}
          value={direction}
          onChange={(event) => {
            const direction = event.currentTarget.value;
            if (
              direction !== "horz" &&
              direction !== "vert" &&
              direction !== "vert270"
            )
              return;
            setDirection(direction);
            controller.run(async () => {
              try {
                await editor.editObjects({
                  action: "textDirection",
                  direction,
                });
              } catch (error) {
                setDirection(first?.direction ?? "horz");
                throw error;
              }
            });
          }}
        >
          <option value="horz">{t.textHorizontal}</option>
          <option value="vert">{t.textClockwise}</option>
          <option value="vert270">{t.textCounterclockwise}</option>
        </select>
      </label>
      {mixed && <p>{t.mixed}</p>}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "textRotation",
              angle: Number(rotation),
            }),
          );
        }}
      >
        <label>
          {t.textRotation}
          <input
            type="number"
            min={-360}
            max={360}
            step="any"
            required
            value={rotation}
            onChange={(event) => setRotation(event.currentTarget.value)}
          />
        </label>
        <button type="submit">
          {t.apply} {t.textRotation}
        </button>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "textInsets",
              left: Number(margins.left),
              top: Number(margins.top),
              right: Number(margins.right),
              bottom: Number(margins.bottom),
            }),
          );
        }}
      >
        {(
          [
            ["left", t.textInsetLeft],
            ["top", t.textInsetTop],
            ["right", t.textInsetRight],
            ["bottom", t.textInsetBottom],
          ] as const
        ).map(([key, label]) => (
          <label key={key}>
            {label}
            <input
              type="number"
              min={0}
              max={14400}
              step="any"
              required
              value={margins[key]}
              onChange={(event) =>
                setMargins({ ...margins, [key]: event.currentTarget.value })
              }
            />
          </label>
        ))}
        <button type="submit">
          {t.apply} {t.textFrameMargins}
        </button>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "textColumns",
              columns: Number(columns),
              gap: Number(gap),
              rtl,
            }),
          );
        }}
      >
        <label>
          {t.textColumnCount}
          <input
            type="number"
            min={1}
            max={16}
            step={1}
            required
            value={columns}
            onChange={(event) => setColumns(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.textColumnGap}
          <input
            type="number"
            min={0}
            max={14400}
            step="any"
            required
            value={gap}
            onChange={(event) => setGap(event.currentTarget.value)}
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={rtl}
            onChange={(event) => setRtl(event.currentTarget.checked)}
          />
          {t.textColumnRtl}
        </label>
        <button type="submit">
          {t.apply} {t.textColumns}
        </button>
      </form>
      <label>
        {t.textAnchor}
        <select
          aria-label={t.textAnchor}
          value={anchor}
          onChange={(event) => {
            const anchor = event.currentTarget.value;
            if (anchor === "t" || anchor === "ctr" || anchor === "b") {
              setAnchor(anchor);
              controller.run(async () => {
                try {
                  await editor.editObjects({ action: "textAnchor", anchor });
                } catch (error) {
                  setAnchor(first?.anchor ?? "t");
                  throw error;
                }
              });
            }
          }}
        >
          <option value="t">{t.alignTop}</option>
          <option value="ctr">{t.alignMiddle}</option>
          <option value="b">{t.alignBottom}</option>
        </select>
      </label>
      <label>
        <input
          type="checkbox"
          checked={wrap}
          onChange={(event) => {
            const wrap = event.currentTarget.checked;
            setWrap(wrap);
            controller.run(async () => {
              try {
                await editor.editObjects({ action: "textWrap", wrap });
              } catch (error) {
                setWrap(first?.wrap ?? true);
                throw error;
              }
            });
          }}
        />
        {t.wrapFrameText}
      </label>
      <label>
        {t.textFit}
        <select
          value={fit}
          aria-label={t.textFit}
          onChange={(event) => {
            const fit = event.currentTarget.value;
            if (fit !== "none" && fit !== "shrink" && fit !== "resize") return;
            setFit(fit);
            controller.run(async () => {
              try {
                await editor.editObjects({ action: "textFit", fit });
              } catch (error) {
                setFit(first?.fit ?? "none");
                throw error;
              }
            });
          }}
        >
          <option value="none">{t.noTextFit}</option>
          <option value="shrink">{t.shrinkFrameText}</option>
          <option value="resize">{t.resizeFrameText}</option>
        </select>
      </label>
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}
