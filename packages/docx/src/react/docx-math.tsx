import { useState } from "react";
import type {
  DocumentEditor,
  DocumentMathFractions,
  DocumentMathScripts,
  DocumentMathExpressions,
} from "../web/editor.js";
import type {
  DocxFractionValue,
  DocxScriptValue,
  DocxMathValue,
} from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

type Catalog =
  | (DocumentMathFractions & { kind: "fraction" })
  | (DocumentMathScripts & { kind: "script" })
  | (DocumentMathExpressions & { kind: "expression" });

export function DocxMath({
  controller,
  state,
  editor,
  disabled,
  insertDisabled,
  kind,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  insertDisabled: boolean;
  kind: "fraction" | "script" | "expression";
}) {
  const t = messages(state.locale);
  const labels =
    kind === "expression"
      ? {
          group: t.mathExpressions,
          load: t.loadExpressions,
          choose: t.chooseExpression,
          insert: t.insertExpression,
          apply: t.applyExpression,
          remove: t.deleteExpression,
        }
      : kind === "fraction"
        ? {
            group: t.mathFractions,
            load: t.loadFractions,
            choose: t.chooseFraction,
            insert: t.insertFraction,
            apply: t.applyFraction,
            remove: t.deleteFraction,
          }
        : {
            group: t.mathScripts,
            load: t.loadScripts,
            choose: t.chooseScript,
            insert: t.insertScript,
            apply: t.applyScript,
            remove: t.deleteScript,
          };
  const [catalog, setCatalog] = useState<Catalog>();
  const [id, setId] = useState<number>();
  const [display, setDisplay] = useState(false);
  const [draft, setDraft] = useState<
    DocxFractionValue | DocxScriptValue | DocxMathValue
  >(
    kind === "expression"
      ? { latex: "\\frac{x_{1}}{2}" }
      : kind === "fraction"
        ? { numerator: "1", denominator: "2" }
        : { base: "X", subscript: "1", superscript: "2" },
  );
  const current = catalog?.items.find((item) => item.id === id);
  const fields =
    "latex" in draft
      ? [
          {
            key: "latex",
            value: draft.latex,
            label: t.mathLatex,
            required: true,
          },
        ]
      : "base" in draft
        ? [
            {
              key: "base",
              value: draft.base,
              label: t.mathBase,
              required: true,
            },
            {
              key: "subscript",
              value: draft.subscript,
              label: t.subscript,
              required: false,
            },
            {
              key: "superscript",
              value: draft.superscript,
              label: t.superscript,
              required: false,
            },
          ]
        : [
            {
              key: "numerator",
              value: draft.numerator,
              label: t.numerator,
              required: true,
            },
            {
              key: "denominator",
              value: draft.denominator,
              label: t.denominator,
              required: true,
            },
          ];
  const invalid =
    fields.some((field) => field.required && !field.value) ||
    fields.reduce((sum, field) => sum + field.value.length, 0) >
      (kind === "expression" ? 131072 : 4096) ||
    ("latex" in draft && !draft.latex.trim()) ||
    ("base" in draft && !draft.subscript && !draft.superscript) ||
    (draft.format &&
      (!Number.isFinite(draft.format.size) ||
        draft.format.size < 0.5 ||
        draft.format.size > 409 ||
        !Number.isInteger(draft.format.size * 2)));
  const families = [
    ...new Set([
      draft.format?.family,
      ...Object.keys(controller.options.resources.profile).filter(
        (key) => !key.includes("|"),
      ),
    ]),
  ].filter((family): family is string => !!family);
  const stale = catalog?.revision !== editor.getSnapshot().revision;
  const selectItem = (item: Catalog["items"][number] | undefined) => {
    setId(item?.id);
    if (item && !item.reason && item.format)
      setDraft(
        "latex" in item
          ? { latex: item.latex, format: { ...item.format } }
          : "base" in item
            ? {
                base: item.base,
                subscript: item.subscript,
                superscript: item.superscript,
                format: { ...item.format },
              }
            : {
                numerator: item.numerator,
                denominator: item.denominator,
                format: { ...item.format },
              },
      );
  };
  const load = async () => {
    const value =
      kind === "expression"
        ? { ...(await editor.mathExpressions()), kind: "expression" as const }
        : kind === "fraction"
          ? { ...(await editor.mathFractions()), kind: "fraction" as const }
          : { ...(await editor.mathScripts()), kind: "script" as const };
    setCatalog(value);
    selectItem(value.items.find((item) => item.id === id) ?? value.items[0]);
  };
  return (
    <section aria-label={labels.group}>
      <fieldset disabled={disabled}>
        <legend>{labels.group}</legend>
        <button type="button" onClick={() => controller.run(load)}>
          {labels.load}
        </button>
        {catalog && catalog.items.length > 0 && (
          <label>
            {labels.choose}
            <select
              aria-label={labels.choose}
              value={id ?? ""}
              onChange={(event) =>
                selectItem(
                  catalog.items.find(
                    (item) => item.id === Number(event.currentTarget.value),
                  ),
                )
              }
            >
              {catalog.items.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.reason ||
                    ("latex" in item
                      ? item.latex
                      : "base" in item
                        ? `${item.base}${item.subscript ? `_(${item.subscript})` : ""}${item.superscript ? `^(${item.superscript})` : ""}`
                        : `${item.numerator}/${item.denominator}`)}
                </option>
              ))}
            </select>
          </label>
        )}
        {fields.map((field) => (
          <label key={field.key}>
            {field.label}
            <input
              value={field.value}
              maxLength={kind === "expression" ? 131072 : 4096}
              required={field.required}
              onChange={(event) =>
                setDraft({ ...draft, [field.key]: event.currentTarget.value })
              }
            />
          </label>
        ))}
        {kind === "expression" && <p>{t.mathLatexHelp}</p>}
        {draft.format && (
          <>
            <label>
              {t.fontFamily}
              <select
                aria-label={t.fontFamily}
                value={draft.format.family}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    format: {
                      ...draft.format!,
                      family: event.currentTarget.value,
                    },
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
                step={0.5}
                value={
                  Number.isFinite(draft.format.size) ? draft.format.size : ""
                }
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    format: {
                      ...draft.format!,
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
                      ...draft.format!,
                      color: event.currentTarget.value.slice(1),
                    },
                  })
                }
              />
            </label>
          </>
        )}
        {kind === "expression" && (
          <label>
            <input
              type="checkbox"
              checked={display}
              onChange={(event) => setDisplay(event.currentTarget.checked)}
            />
            {t.displayExpression}
          </label>
        )}
        <button
          type="button"
          disabled={insertDisabled || !!invalid}
          onClick={() =>
            controller.run(async () => {
              if ("latex" in draft) await editor.insertMath(draft, display);
              else if ("base" in draft) await editor.insertMathScript(draft);
              else await editor.insertMathFraction(draft);
              setCatalog(undefined);
              setId(undefined);
              editor.focus();
            })
          }
        >
          {labels.insert}
        </button>
        <button
          type="button"
          disabled={stale || !current || !!current.reason || !!invalid}
          onClick={() =>
            controller.run(async () => {
              if (!catalog || id === undefined) return;
              if (catalog.kind === "expression" && "latex" in draft)
                await editor.editMath(catalog, id, draft);
              else if (catalog.kind === "script" && "base" in draft)
                await editor.editMathScript(catalog, id, draft);
              else if (catalog.kind === "fraction" && "numerator" in draft)
                await editor.editMathFraction(catalog, id, draft);
              await load();
            })
          }
        >
          {labels.apply}
        </button>
        <button
          type="button"
          disabled={stale || !current || !!current.reason}
          onClick={() =>
            controller.run(async () => {
              if (!catalog || id === undefined) return;
              if (catalog.kind === "expression")
                await editor.editMath(catalog, id, null);
              else if (catalog.kind === "script")
                await editor.editMathScript(catalog, id, null);
              else await editor.editMathFraction(catalog, id, null);
              await load();
            })
          }
        >
          {labels.remove}
        </button>
        {current?.reason && <p>{current.reason}</p>}
      </fieldset>
    </section>
  );
}
