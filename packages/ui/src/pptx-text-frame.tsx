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
  const [autofit, setAutofit] = useState(first?.autofit ?? false);
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
      ["left", "top", "right", "bottom", "anchor", "wrap", "autofit"] as const
    ).some((key) => object.textFrame[key] !== first?.[key]),
  );
  return (
    <fieldset disabled={disabled || objects.length === 0 || !!reason}>
      <legend>{t.textFrame}</legend>
      {mixed && <p>{t.mixed}</p>}
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
        <input
          type="checkbox"
          checked={autofit}
          onChange={(event) => {
            const autofit = event.currentTarget.checked;
            setAutofit(autofit);
            controller.run(async () => {
              try {
                await editor.editObjects({ action: "textFit", autofit });
              } catch (error) {
                setAutofit(first?.autofit ?? false);
                throw error;
              }
            });
          }}
        />
        {t.shrinkFrameText}
      </label>
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}
