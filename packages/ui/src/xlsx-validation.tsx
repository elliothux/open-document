import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  validationKinds,
  validationOperators,
  type XlsxDataValidation,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxValidation({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.currentState,
    current = query.dataValidation;
  const [rule, setRule] = useState<XlsxDataValidation>(
    current.rule ?? {
      kind: "whole",
      operator: "between",
      formula1: "1",
      formula2: "10",
      allowBlank: true,
      showErrorMessage: true,
      errorStyle: "stop",
      errorTitle: "",
      error: "",
      showInputMessage: false,
      promptTitle: "",
      prompt: "",
      showDropDown: false,
    },
  );
  const kinds = [
    t.validationAny,
    t.validationWhole,
    t.validationDecimal,
    t.validationDate,
    t.validationTime,
    t.validationLength,
    t.validationList,
    t.validationCustom,
  ];
  const operators = [
    t.validationBetween,
    t.validationNotBetween,
    t.validationEqual,
    t.validationNotEqual,
    t.validationLess,
    t.validationLessEqual,
    t.validationGreater,
    t.validationGreaterEqual,
  ];
  return (
    <section aria-label={t.dataValidation}>
      {current.promptVisible && current.rule && (
        <p role="status">
          {current.rule.promptTitle} {current.rule.prompt}
        </p>
      )}
      {current.rule?.kind === "list" && !current.rule.showDropDown && (
        <label>
          {t.validationChoices}
          <select
            aria-label={t.validationChoices}
            value=""
            disabled={
              disabled || !!current.optionsReason || !current.options.length
            }
            onChange={(event) => {
              const index = Number(event.currentTarget.value);
              if (Number.isInteger(index) && index >= 0)
                controller.run(() =>
                  editor.editSheet({
                    action: "validationValue",
                    index,
                    sourceRevision: query.revision,
                  }),
                );
            }}
          >
            <option value="">{t.choose}</option>
            {current.options.map((value, index) => (
              <option key={index} value={index}>
                {value || t.validationBlank}
              </option>
            ))}
          </select>
        </label>
      )}
      {current.optionsReason && current.rule?.kind === "list" && (
        <p>{current.optionsReason}</p>
      )}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editSheet({
              action: "validation",
              range: query.selection.address,
              rule,
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !!current.readOnlyReason}>
          <legend>{t.dataValidation}</legend>
          {current.mixed && <p>{t.mixed}</p>}
          <label>
            {t.validationKind}
            <select
              aria-label={t.validationKind}
              value={rule.kind}
              onChange={(event) => {
                const kind = validationKinds.find(
                  (k) => k === event.currentTarget.value,
                );
                if (kind) setRule({ ...rule, kind });
              }}
            >
              {validationKinds.map((kind, index) => (
                <option key={kind} value={kind}>
                  {kinds[index]}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t.validationOperator}
            <select
              aria-label={t.validationOperator}
              value={rule.operator}
              disabled={["none", "list", "custom"].includes(rule.kind)}
              onChange={(event) => {
                const operator = validationOperators.find(
                  (o) => o === event.currentTarget.value,
                );
                if (operator) setRule({ ...rule, operator });
              }}
            >
              {validationOperators.map((value, index) => (
                <option key={value} value={value}>
                  {operators[index]}
                </option>
              ))}
            </select>
          </label>
          {(["formula1", "formula2"] as const).map((key, index) => (
            <label key={key}>
              {index ? t.validationFormula2 : t.validationFormula1}
              <input
                value={rule[key]}
                maxLength={8192}
                disabled={
                  rule.kind === "none" ||
                  (index === 1 &&
                    (["list", "custom"].includes(rule.kind) ||
                      !["between", "notBetween"].includes(rule.operator)))
                }
                onChange={(event) =>
                  setRule({ ...rule, [key]: event.currentTarget.value })
                }
              />
            </label>
          ))}
          {(
            [
              ["allowBlank", t.validationAllowBlank],
              ["showErrorMessage", t.validationShowError],
              ["showInputMessage", t.validationShowPrompt],
              ["showDropDown", t.validationHideList],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              <input
                type="checkbox"
                checked={rule[key]}
                onChange={(event) =>
                  setRule({ ...rule, [key]: event.currentTarget.checked })
                }
              />
              {label}
            </label>
          ))}
          <label>
            {t.validationErrorStyle}
            <select
              aria-label={t.validationErrorStyle}
              value={rule.errorStyle}
              onChange={(event) => {
                const errorStyle = event.currentTarget.value;
                if (
                  errorStyle === "stop" ||
                  errorStyle === "warning" ||
                  errorStyle === "information"
                )
                  setRule({ ...rule, errorStyle });
              }}
            >
              <option value="stop">{t.validationStop}</option>
              <option value="warning">{t.validationWarning}</option>
              <option value="information">{t.validationInformation}</option>
            </select>
          </label>
          {(
            [
              ["errorTitle", t.validationErrorTitle],
              ["error", t.validationError],
              ["promptTitle", t.validationPromptTitle],
              ["prompt", t.validationPrompt],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                maxLength={key.endsWith("Title") ? 32 : 255}
                value={rule[key]}
                onChange={(event) =>
                  setRule({ ...rule, [key]: event.currentTarget.value })
                }
              />
            </label>
          ))}
          <button type="submit">
            {t.apply} {t.dataValidation}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editSheet({
                  action: "validation",
                  range: query.selection.address,
                  rule: null,
                }),
              )
            }
          >
            {t.clearValidation}
          </button>
        </fieldset>
      </form>
      {current.readOnlyReason && <p>{current.readOnlyReason}</p>}
    </section>
  );
}
