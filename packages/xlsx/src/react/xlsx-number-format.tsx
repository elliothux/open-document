import { useEffect, useState } from "react";
import { messages } from "@open-document/ui/messages";
import { xlsxNumberFormats } from "../web/xlsx.js";
import type { PanelProps } from "./context.js";

export function XlsxNumberFormat({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const t = messages(state.locale);
  const editor = file.editor;
  const { formatting, date1904 } = editor.currentState;
  const numberFormat = formatting.numberFormat ?? "";
  const [samples, setSamples] = useState<string[]>([]);
  useEffect(() => {
    let active = true;
    void editor.data.numberFormatSamples(xlsxNumberFormats).then(
      (result) => {
        if (active) setSamples(result);
      },
      () => {
        if (active) setSamples([]);
      },
    );
    return () => {
      active = false;
    };
  }, [editor, date1904]);

  return (
    <select
      className="od-xlsx-number-format"
      aria-label={t.cellNumberFormat}
      disabled={disabled || !!formatting.readOnlyReason}
      value={numberFormat}
      onChange={(event) => {
        const numberFormat = event.currentTarget.value;
        controller.run(() => editor.formatCells({ numberFormat }));
      }}
    >
      <option value="" disabled>
        {t.mixed}
      </option>
      {numberFormat &&
        !xlsxNumberFormats.some((format) => format === numberFormat) && (
          <option value={numberFormat}>{numberFormat}</option>
        )}
      {xlsxNumberFormats.map((format, index) => (
        <option key={format} value={format}>
          {samples[index] ? `${format} · ${samples[index]}` : format}
        </option>
      ))}
    </select>
  );
}
