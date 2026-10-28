import { useState } from "react";
import { checkXlsxDrawingFrame, type XlsxDrawingFrame } from "../web/xlsx.js";
import type { UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function AnalysisFrameEditor({
  frame,
  kind,
  state,
  disabled,
  apply,
}: {
  frame: XlsxDrawingFrame;
  kind: "slicer" | "timeline";
  state: UiSnapshot;
  disabled: boolean;
  apply: (frame: XlsxDrawingFrame) => void;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState(frame);
  let valid = true;
  try {
    checkXlsxDrawingFrame(draft);
  } catch {
    valid = false;
  }
  return (
    <fieldset disabled={disabled}>
      <legend>{kind === "timeline" ? t.timelineFrame : t.slicerFrame}</legend>
      <label>
        {kind === "timeline" ? t.timelineAnchor : t.slicerAnchor}
        <select
          aria-label={kind === "timeline" ? t.timelineAnchor : t.slicerAnchor}
          value={draft.anchor}
          onChange={(event) => {
            const anchor = event.currentTarget.value;
            if (anchor === "fixed" || anchor === "move" || anchor === "size")
              setDraft({ ...draft, anchor });
          }}
        >
          <option value="fixed">{t.xlsxPictureFixed}</option>
          <option value="move">{t.xlsxPictureMove}</option>
          <option value="size">{t.xlsxPictureSize}</option>
        </select>
      </label>
      {(
        [
          ["x", t.objectX],
          ["y", t.objectY],
          ["width", t.objectWidth],
          ["height", t.objectHeight],
        ] as const
      ).map(([key, label]) => (
        <label key={key}>
          {label}
          <input
            type="number"
            min={key === "x" || key === "y" ? 0 : 0.1}
            max={key === "x" || key === "y" ? 1e9 : 14400}
            step="any"
            value={Number.isFinite(draft[key]) ? draft[key] : ""}
            onChange={(event) =>
              setDraft({ ...draft, [key]: event.currentTarget.valueAsNumber })
            }
          />
        </label>
      ))}
      <button type="button" disabled={!valid} onClick={() => apply(draft)}>
        {kind === "timeline" ? t.timelineFrameApply : t.slicerFrameApply}
      </button>
    </fieldset>
  );
}
