import { useEffect, useState } from "react";
import type { XlsxTable, XlsxTableStyle } from "@open-document/web/xlsx";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";

export function XlsxTableStyleForm({
  table,
  ...props
}: PanelProps & { table: XlsxTable }) {
  const [style, setStyle] = useState<XlsxTableStyle>({
    name: table.style,
    firstColumn: table.firstColumn,
    lastColumn: table.lastColumn,
    rowStripes: table.rowStripes,
    columnStripes: table.columnStripes,
  });
  useEffect(
    () =>
      setStyle({
        name: table.style,
        firstColumn: table.firstColumn,
        lastColumn: table.lastColumn,
        rowStripes: table.rowStripes,
        columnStripes: table.columnStripes,
      }),
    [
      table.style,
      table.firstColumn,
      table.lastColumn,
      table.rowStripes,
      table.columnStripes,
    ],
  );
  if (props.file.format !== "xlsx") return null;
  const editor = props.file.editor,
    t = messages(props.state.locale);
  const choices = ["Medium", "Light", "Dark"].flatMap((family) =>
    Array.from(
      { length: family === "Medium" ? 28 : family === "Light" ? 21 : 11 },
      (_, index) => `TableStyle${family}${index + 1}`,
    ),
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        props.controller.run(() =>
          editor.editSheet({ action: "tableStyle", id: table.id, style }),
        );
      }}
    >
      <fieldset disabled={!!table.readOnlyReason}>
        <legend>{t.tableStyle}</legend>
        <label>
          {t.tableStyleName}
          <select
            aria-label={t.tableStyleName}
            value={style.name ?? ""}
            onChange={(event) =>
              setStyle({ ...style, name: event.currentTarget.value || null })
            }
          >
            <option value="">{t.tableStyleNone}</option>
            {style.name && !choices.includes(style.name) && (
              <option value={style.name}>{style.name}</option>
            )}
            {choices.map((name) => (
              <option key={name} value={name}>
                {name.replace(/^TableStyle([A-Za-z]+)([0-9]+)$/, "$1 $2")}
              </option>
            ))}
          </select>
        </label>
        {(
          ["firstColumn", "lastColumn", "rowStripes", "columnStripes"] as const
        ).map((key) => (
          <label key={key}>
            <input
              type="checkbox"
              checked={style[key]}
              onChange={(event) =>
                setStyle({ ...style, [key]: event.currentTarget.checked })
              }
            />
            {
              t[
                key === "firstColumn"
                  ? "tableFirstColumn"
                  : key === "lastColumn"
                    ? "tableLastColumn"
                    : key === "rowStripes"
                      ? "tableRowStripes"
                      : "tableColumnStripes"
              ]
            }
          </label>
        ))}
        <button type="submit">{t.applyTableStyle}</button>
      </fieldset>
    </form>
  );
}
