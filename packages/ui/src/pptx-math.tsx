import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxMathValue } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxMath({
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
  const object =
    query.selection.objects.length === 1
      ? query.objects.find((o) => o.id === query.selection.object)
      : undefined;
  const [node, setNode] = useState(object?.equations[0]?.node);
  const current = object?.equations.find((item) => item.node === node);
  const [draft, setDraft] = useState<PptxMathValue>(
    current
      ? { latex: current.latex, format: { ...current.format } }
      : {
          latex: "\\frac{x_{1}}{2}",
          format: { family: "Cambria Math", size: 24, color: "000000" },
        },
  );
  const families = [
    ...new Set([
      draft.format.family,
      ...Object.keys(controller.options.resources.profile).filter(
        (key) => !key.includes("|"),
      ),
    ]),
  ];
  const invalid =
    !draft.latex.trim() ||
    !Number.isFinite(draft.format.size) ||
    draft.format.size < 0.5 ||
    draft.format.size > 409;
  const target =
    current && object
      ? { object: object.id, revision: query.revision, node: current.node }
      : undefined;
  const append = object?.kind === "text" || object?.kind === "shape";
  return (
    <section aria-label={t.mathExpressions}>
      <fieldset disabled={disabled || !!query.readOnlyReason}>
        <legend>{t.mathExpressions}</legend>
        {!!object?.equations.length && (
          <label>
            {t.chooseExpression}
            <select
              aria-label={t.chooseExpression}
              value={node}
              onChange={(event) => {
                const item = object.equations.find(
                  (item) => item.node === Number(event.currentTarget.value),
                );
                setNode(item?.node);
                if (item)
                  setDraft({ latex: item.latex, format: { ...item.format } });
              }}
            >
              {object.equations.map((item) => (
                <option key={item.node} value={item.node}>
                  {item.latex}
                </option>
              ))}
            </select>
          </label>
        )}
        <label>
          {t.mathLatex}
          <input
            value={draft.latex}
            maxLength={131072}
            onChange={(event) =>
              setDraft({ ...draft, latex: event.currentTarget.value })
            }
          />
        </label>
        <p>{t.mathLatexHelp}</p>
        <label>
          {t.fontFamily}
          <select
            aria-label={t.fontFamily}
            value={draft.format.family}
            onChange={(event) =>
              setDraft({
                ...draft,
                format: { ...draft.format, family: event.currentTarget.value },
              })
            }
          >
            {families.map((family) => (
              <option key={family} value={family}>
                {family}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.fontSize}
          <input
            type="number"
            min={0.5}
            max={409}
            step={0.01}
            value={Number.isFinite(draft.format.size) ? draft.format.size : ""}
            onChange={(event) =>
              setDraft({
                ...draft,
                format: {
                  ...draft.format,
                  size: event.currentTarget.valueAsNumber,
                },
              })
            }
          />
        </label>
        <label>
          {t.textColor}
          <input
            type="color"
            value={`#${draft.format.color}`}
            onChange={(event) =>
              setDraft({
                ...draft,
                format: {
                  ...draft.format,
                  color: event.currentTarget.value.slice(1),
                },
              })
            }
          />
        </label>
        <button
          type="button"
          disabled={invalid}
          onClick={() =>
            controller.run(() =>
              editor.editObjects({
                action: "insertMath",
                ...draft,
                x: 72,
                y: 72,
                width: 480,
                height: 240,
              }),
            )
          }
        >
          {t.insertExpression}
        </button>
        {(["start", "end"] as const).map((position) => (
          <button
            key={position}
            type="button"
            disabled={invalid || !append || !!object?.readOnlyReason}
            onClick={() =>
              controller.run(() =>
                editor.editObjects({
                  action: "appendMath",
                  position,
                  ...draft,
                }),
              )
            }
          >
            {position === "start"
              ? t.insertExpressionStart
              : t.insertExpressionEnd}
          </button>
        ))}
        <button
          type="button"
          disabled={invalid || !target || !!current?.reason}
          onClick={() =>
            controller.run(() =>
              target
                ? editor.editObjects({ action: "updateMath", target, ...draft })
                : Promise.resolve(),
            )
          }
        >
          {t.applyExpression}
        </button>
        <button
          type="button"
          disabled={!target || !!current?.reason}
          onClick={() =>
            controller.run(() =>
              target
                ? editor.editObjects({ action: "deleteMath", target })
                : Promise.resolve(),
            )
          }
        >
          {t.deleteExpression}
        </button>
        {current?.reason && <p>{current.reason}</p>}
      </fieldset>
    </section>
  );
}
