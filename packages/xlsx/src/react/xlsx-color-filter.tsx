import { useState } from "react";
import type { XlsxColorFilter, XlsxFilterColumn } from "../web/xlsx.js";
import type { UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function XlsxColorFilterForm({
  criterion,
  column,
  apply,
  disabled,
  state,
}: {
  criterion: XlsxFilterColumn | undefined;
  column: number;
  apply: (rule: XlsxColorFilter) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale),
    initial = criterion?.kind === "color" ? criterion : undefined;
  const [cellColor, setCellColor] = useState(initial?.cellColor ?? true);
  const [color, setColor] = useState(`#${initial?.color ?? "000000"}`);
  const [automatic, setAutomatic] = useState(initial?.color === null);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply({
          kind: "color",
          column,
          cellColor,
          color: automatic ? null : color.slice(1),
        });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterColors}</legend>
        <label>
          {t.filterColorTarget}
          <select
            aria-label={t.filterColorTarget}
            value={cellColor ? "fill" : "font"}
            onChange={(event) =>
              setCellColor(event.currentTarget.value === "fill")
            }
          >
            <option value="fill">{t.cellFill}</option>
            <option value="font">{t.textColor}</option>
          </select>
        </label>
        <label>
          {t.filterColorValue}
          <input
            type="color"
            value={color}
            disabled={automatic}
            onChange={(event) => setColor(event.currentTarget.value)}
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={automatic}
            onChange={(event) => setAutomatic(event.currentTarget.checked)}
          />
          {cellColor ? t.filterNoFill : t.filterAutomaticFont}
        </label>
        <button type="submit">{t.filterColorApply}</button>
      </fieldset>
    </form>
  );
}
