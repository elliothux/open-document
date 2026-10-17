import { useState } from "react";
import type { PptxLineEnd } from "@open-document/web/pptx";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxLineEnds({
  editor,
  controller,
  state,
  disabled,
}: {
  editor: PresentationEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const objects = editor.query.objects.filter((o) =>
    editor.query.selection.objects.includes(o.id),
  );
  const reason = objects.find((o) => o.appearance.lineEndReason)?.appearance
    .lineEndReason;
  return (
    <fieldset disabled={disabled || !!reason || !objects.length}>
      <legend>{t.lineEnds}</legend>
      {(["head", "tail"] as const).map((side) => (
        <LineEndForm
          key={side}
          side={side}
          value={
            objects[0]?.appearance[side === "head" ? "headEnd" : "tailEnd"]
          }
          mixed={objects.some(
            (o) =>
              JSON.stringify(
                o.appearance[side === "head" ? "headEnd" : "tailEnd"],
              ) !==
              JSON.stringify(
                objects[0]?.appearance[side === "head" ? "headEnd" : "tailEnd"],
              ),
          )}
          state={state}
          apply={(end) =>
            controller.run(() =>
              editor.editObjects({ action: "lineEnd", side, end }),
            )
          }
        />
      ))}
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}

function LineEndForm({
  side,
  value,
  mixed,
  state,
  apply,
}: {
  side: "head" | "tail";
  value: PptxLineEnd | undefined;
  mixed: boolean;
  state: UiSnapshot;
  apply: (end: PptxLineEnd | null) => void;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState<PptxLineEnd>(
    value ?? { kind: "none", width: "med", length: "med" },
  );
  const kinds: [PptxLineEnd["kind"], string][] = [
    ["none", t.lineEndNone],
    ["triangle", t.triangle],
    ["stealth", t.lineEndStealth],
    ["diamond", t.diamond],
    ["oval", t.ellipse],
    ["arrow", t.lineEndArrow],
  ];
  const sizes: [PptxLineEnd["width"], string][] = [
    ["sm", t.lineEndSmall],
    ["med", t.lineEndMedium],
    ["lg", t.lineEndLarge],
  ];
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply(draft);
      }}
    >
      <fieldset>
        <legend>{side === "head" ? t.lineEndHead : t.lineEndTail}</legend>
        {mixed && <p>{t.mixed}</p>}
        <label>
          {t.lineEndKind}
          <select
            aria-label={t.lineEndKind}
            value={draft.kind}
            onChange={(event) => {
              const kind = kinds.find(
                ([kind]) => kind === event.currentTarget.value,
              )?.[0];
              if (kind) setDraft({ ...draft, kind });
            }}
          >
            {kinds.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>
        {(["width", "length"] as const).map((key) => (
          <label key={key}>
            {key === "width" ? t.lineEndWidth : t.lineEndLength}
            <select
              aria-label={key === "width" ? t.lineEndWidth : t.lineEndLength}
              value={draft[key]}
              onChange={(event) => {
                const size = sizes.find(
                  ([size]) => size === event.currentTarget.value,
                )?.[0];
                if (size) setDraft({ ...draft, [key]: size });
              }}
            >
              {sizes.map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
        ))}
        <button type="submit">{t.applyLineEnd}</button>
        <button type="button" onClick={() => apply(null)}>
          {t.resetLineEnd}
        </button>
      </fieldset>
    </form>
  );
}
