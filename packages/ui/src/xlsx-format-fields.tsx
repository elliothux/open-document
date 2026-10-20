import type {
  XlsxCellFormat,
  XlsxCellBorder,
  XlsxFormatting,
} from "@open-document/web/xlsx";
import { xlsxNumberFormats } from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxFormatFields({
  format,
  onChange,
  current,
  families,
  state,
  prefix = "",
}: {
  format: XlsxCellFormat;
  onChange(format: XlsxCellFormat): void;
  current?: XlsxFormatting;
  families: string[];
  state: UiSnapshot;
  prefix?: string;
}) {
  const t = messages(state.locale);
  function set<K extends keyof XlsxCellFormat>(
    key: K,
    value: XlsxCellFormat[K],
  ) {
    const next = { ...format };
    if (value === undefined) delete next[key];
    else next[key] = value;
    onChange(next);
  }
  const aria = (label: string) => (prefix ? prefix + label : undefined);
  const options = (values: readonly string[]) => (
    <>
      <option value="">{t.keepStyleProperty}</option>
      {values.map((value) => (
        <option key={value} value={value}>
          {value}
        </option>
      ))}
    </>
  );
  return (
    <>
      <label>
        {t.fontFamily}
        <select
          aria-label={aria(t.fontFamily)}
          value={format.family ?? ""}
          onChange={(event) =>
            set("family", event.currentTarget.value || undefined)
          }
        >
          {format.family && !families.includes(format.family) && (
            <option value={format.family}>{format.family}</option>
          )}
          {options(families)}
        </select>
      </label>
      <label>
        {t.fontSize}
        <input
          aria-label={aria(t.fontSize)}
          type="number"
          min={1}
          max={409}
          step="any"
          value={format.size ?? ""}
          placeholder={
            current
              ? current.size === null
                ? t.mixed
                : String(current.size)
              : t.keepStyleProperty
          }
          onChange={(event) =>
            set(
              "size",
              event.currentTarget.value === ""
                ? undefined
                : Number(event.currentTarget.value),
            )
          }
        />
      </label>
      {(["bold", "italic", "underline", "strike", "wrap"] as const).map(
        (key) => (
          <label key={key}>
            {t[key]}
            <select
              aria-label={aria(t[key])}
              value={format[key] === undefined ? "" : String(format[key])}
              onChange={(event) =>
                set(
                  key,
                  event.currentTarget.value === ""
                    ? undefined
                    : event.currentTarget.value === "true",
                )
              }
            >
              <option value="">
                {current?.[key] === null ? t.mixed : t.keepStyleProperty}
              </option>
              <option value="true">{t.styleOn}</option>
              <option value="false">{t.styleOff}</option>
            </select>
          </label>
        ),
      )}
      {current &&
        (["locked", "formulaHidden"] as const).map((key) => (
          <label key={key}>
            {t[key]}
            <select
              aria-label={t[key]}
              value={format[key] === undefined ? "" : String(format[key])}
              onChange={(event) =>
                set(
                  key,
                  event.currentTarget.value === ""
                    ? undefined
                    : event.currentTarget.value === "true",
                )
              }
            >
              <option value="">
                {current[key] === null ? t.mixed : t.keepStyleProperty}
              </option>
              <option value="true">{t.styleOn}</option>
              <option value="false">{t.styleOff}</option>
            </select>
          </label>
        ))}
      {current && <p>{t.cellProtectionHint}</p>}
      <label>
        {t.superscript + " / " + t.subscript}
        <select
          aria-label={aria(t.superscript + " / " + t.subscript)}
          value={format.script ?? ""}
          onChange={(event) =>
            set(
              "script",
              event.currentTarget.value === ""
                ? undefined
                : (event.currentTarget.value as XlsxCellFormat["script"]),
            )
          }
        >
          <option value="">
            {current?.script === null ? t.mixed : t.keepStyleProperty}
          </option>
          {(["baseline", "superscript", "subscript"] as const).map((script) => (
            <option key={script} value={script}>
              {t[script]}
            </option>
          ))}
        </select>
      </label>
      {(["color", "fill"] as const).map((key) => (
        <label key={key}>
          {key === "color" ? t.textColor : t.cellFill}
          <input
            aria-label={aria(key === "color" ? t.textColor : t.cellFill)}
            value={format[key] ?? ""}
            pattern="[0-9A-Fa-f]{6}"
            placeholder={
              current ? (current[key] ?? t.mixed) : t.keepStyleProperty
            }
            onChange={(event) =>
              set(key, event.currentTarget.value || undefined)
            }
          />
        </label>
      ))}
      <label>
        <input
          aria-label={aria(t.noCellFill)}
          type="checkbox"
          checked={format.fill === ""}
          onChange={(event) =>
            set("fill", event.currentTarget.checked ? "" : undefined)
          }
        />
        {t.noCellFill}
      </label>
      <label>
        {t.cellHorizontal}
        <select
          aria-label={aria(t.cellHorizontal)}
          value={format.horizontal ?? ""}
          onChange={(event) =>
            set(
              "horizontal",
              event.currentTarget.value === ""
                ? undefined
                : (event.currentTarget.value as XlsxCellFormat["horizontal"]),
            )
          }
        >
          {options(["general", "left", "center", "right"])}
        </select>
      </label>
      <label>
        {t.cellVertical}
        <select
          aria-label={aria(t.cellVertical)}
          value={format.vertical ?? ""}
          onChange={(event) =>
            set(
              "vertical",
              event.currentTarget.value === ""
                ? undefined
                : (event.currentTarget.value as XlsxCellFormat["vertical"]),
            )
          }
        >
          {options(["top", "center", "bottom"])}
        </select>
      </label>
      <label>
        {t.cellNumberFormat}
        <select
          aria-label={aria(t.cellNumberFormat)}
          value={format.numberFormat ?? ""}
          onChange={(event) =>
            set("numberFormat", event.currentTarget.value || undefined)
          }
        >
          {options(xlsxNumberFormats)}
        </select>
      </label>
      {(["left", "right", "top", "bottom"] as const).map((side) => (
        <fieldset key={side}>
          <legend>{t[`${side}CellBorder`]}</legend>
          <label>
            {t.cellBorderStyle}
            <select
              aria-label={aria(
                t[`${side}CellBorder`] + ": " + t.cellBorderStyle,
              )}
              value={format[side]?.style ?? ""}
              onChange={(event) =>
                set(
                  side,
                  event.currentTarget.value === ""
                    ? undefined
                    : {
                        style: event.currentTarget
                          .value as XlsxCellBorder["style"],
                        color:
                          format[side]?.color ??
                          current?.[side]?.color ??
                          "000000",
                      },
                )
              }
            >
              {options(["none", "thin", "medium", "thick", "double"])}
            </select>
          </label>
          <label>
            {t.textColor}
            <input
              aria-label={aria(t[`${side}CellBorder`] + ": " + t.textColor)}
              disabled={!format[side]}
              value={format[side]?.color ?? "000000"}
              required
              pattern="[0-9A-Fa-f]{6}"
              onChange={(event) =>
                set(side, {
                  style: format[side]?.style ?? "thin",
                  color: event.currentTarget.value,
                })
              }
            />
          </label>
        </fieldset>
      ))}
    </>
  );
}
