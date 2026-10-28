import { useEffect, useState } from "react";
import {
  xlsxTableStyleRegions,
  xlsxBorderStyles,
  type XlsxTableStyleElement,
  type XlsxCellBorder,
} from "../web/xlsx.js";
import type { PanelProps } from "./panels.js";
import { messages } from "@open-document/ui/messages";
import { XlsxFormatFields } from "./xlsx-format-fields.js";
import { tableStyleNames } from "./xlsx-table-style.js";

export function XlsxTableStyleDefinitions(props: PanelProps) {
  const [original, setOriginal] = useState<string | null>(null),
    [name, setName] = useState(""),
    [elements, setElements] = useState<XlsxTableStyleElement[]>([]),
    [kind, setKind] = useState<XlsxTableStyleElement["kind"]>("wholeTable"),
    [replacement, setReplacement] = useState<string | null>(null);
  const query =
    props.file.format === "xlsx" ? props.file.editor.currentState : null;
  const selected = query?.tableStyles.find((style) => style.name === original);
  const actual = JSON.stringify(selected);
  useEffect(() => {
    if (selected) {
      setName(selected.name);
      setElements(selected.elements);
    } else if (original !== null) {
      setOriginal(null);
      setName("");
      setElements([]);
    }
  }, [actual, original]);
  if (props.file.format !== "xlsx" || !query) return null;
  const editor = props.file.editor,
    t = messages(props.state.locale),
    element = elements.find((element) => element.kind === kind);
  const reason =
    selected?.readOnlyReason || query.sheetRenameReason || query.readOnlyReason;
  const disabled =
    props.disabled ||
    !!reason ||
    query.sheets.find((sheet) => sheet.id === query.sheet)?.protected;
  const choose = (name: string) => {
    const choice = query.tableStyles.find((style) => style.name === name);
    setOriginal(choice?.name ?? null);
    setName(choice?.name ?? "");
    setElements(choice?.elements ?? []);
    setReplacement(null);
  };
  const update = (next: XlsxTableStyleElement) =>
    setElements(
      elements.map((element) => (element.kind === kind ? next : element)),
    );
  const styles = [
    ...tableStyleNames.filter(
      (name) =>
        !query.tableStyles.some(
          (style) => style.name.toUpperCase() === name.toUpperCase(),
        ),
    ),
    ...query.tableStyles
      .filter((style) => !style.readOnlyReason && style.name !== original)
      .map((style) => style.name),
  ];
  return (
    <fieldset disabled={disabled}>
      <legend>{t.tableStyleDefinition}</legend>
      {reason && <p role="status">{reason}</p>}
      <label>
        {t.tableChoice}
        <select
          aria-label={t.tableStyleDefinition + ": " + t.tableChoice}
          value={original ?? ""}
          onChange={(event) => choose(event.currentTarget.value)}
        >
          <option value="">{t.newTableStyle}</option>
          {query.tableStyles.map((style) => (
            <option
              key={style.name}
              value={style.name}
              disabled={!!style.readOnlyReason}
            >
              {style.name}
            </option>
          ))}
        </select>
      </label>
      <button type="button" onClick={() => choose("")}>
        {t.newTableStyle}
      </button>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          props.controller.run(async () => {
            await editor.editSheet({
              action: "tableStyleDefinition",
              original,
              name,
              elements,
            });
            setOriginal(name);
          });
        }}
      >
        <label>
          {t.tableStyleName}
          <input
            aria-label={t.tableStyleDefinition + ": " + t.tableStyleName}
            required
            maxLength={255}
            value={name}
            onChange={(event) => setName(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.tableStyleRegion}
          <select
            aria-label={t.tableStyleRegion}
            value={kind}
            onChange={(event) =>
              setKind(
                event.currentTarget.value as XlsxTableStyleElement["kind"],
              )
            }
          >
            {xlsxTableStyleRegions.map((kind) => (
              <option key={kind} value={kind}>
                {t[`tableRegion_${kind}`]}
              </option>
            ))}
          </select>
        </label>
        <label>
          <input
            type="checkbox"
            checked={!!element}
            onChange={(event) =>
              setElements(
                event.currentTarget.checked
                  ? [
                      ...elements,
                      {
                        kind,
                        size: 1,
                        format: {},
                        vertical: null,
                        horizontal: null,
                      },
                    ]
                  : elements.filter((element) => element.kind !== kind),
              )
            }
          />
          {t.includeTableRegion}
        </label>
        <fieldset disabled={!element}>
          {element && (
            <>
              {kind.endsWith("Stripe") && (
                <label>
                  {t.tableStripeSize}
                  <input
                    type="number"
                    required
                    min={1}
                    max={1048576}
                    step={1}
                    value={Number.isFinite(element.size) ? element.size : ""}
                    onChange={(event) =>
                      update({
                        ...element,
                        size: event.currentTarget.valueAsNumber,
                      })
                    }
                  />
                </label>
              )}
              <XlsxFormatFields
                format={element.format}
                onChange={(format) => update({ ...element, format })}
                state={props.state}
                families={Object.keys(
                  props.controller.options.resources.profile,
                ).filter((key) => !key.includes("|"))}
                prefix={t.tableStyleDefinition + ": "}
              />
              {(["vertical", "horizontal"] as const).map((side) => (
                <fieldset key={side}>
                  <legend>
                    {side === "vertical"
                      ? t.tableInnerVertical
                      : t.tableInnerHorizontal}
                  </legend>
                  <label>
                    {t.cellBorderStyle}
                    <select
                      aria-label={
                        (side === "vertical"
                          ? t.tableInnerVertical
                          : t.tableInnerHorizontal) +
                        ": " +
                        t.cellBorderStyle
                      }
                      value={element[side]?.style ?? ""}
                      onChange={(event) =>
                        update({
                          ...element,
                          [side]:
                            event.currentTarget.value === ""
                              ? null
                              : {
                                  style: event.currentTarget
                                    .value as XlsxCellBorder["style"],
                                  color: element[side]?.color ?? "000000",
                                },
                        })
                      }
                    >
                      <option value="">{t.keepStyleProperty}</option>
                      {xlsxBorderStyles.map((style) => (
                        <option key={style} value={style}>
                          {style}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    {t.textColor}
                    <input
                      aria-label={
                        (side === "vertical"
                          ? t.tableInnerVertical
                          : t.tableInnerHorizontal) +
                        ": " +
                        t.textColor
                      }
                      disabled={!element[side]}
                      pattern="[0-9A-Fa-f]{6}"
                      value={element[side]?.color ?? "000000"}
                      onChange={(event) =>
                        update({
                          ...element,
                          [side]: {
                            style: element[side]?.style ?? "thin",
                            color: event.currentTarget.value,
                          },
                        })
                      }
                    />
                  </label>
                </fieldset>
              ))}
            </>
          )}
        </fieldset>
        <button type="submit">{t.saveTableStyle}</button>
      </form>
      <p>{t.deleteTableStyleHelp}</p>
      <label>
        {t.replacementTableStyle}
        <select
          aria-label={t.replacementTableStyle}
          value={replacement ?? ""}
          onChange={(event) =>
            setReplacement(event.currentTarget.value || null)
          }
        >
          <option value="">{t.tableStyleNone}</option>
          {styles.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </select>
      </label>
      <button
        type="button"
        disabled={!original}
        onClick={() => {
          if (original)
            props.controller.run(async () => {
              await editor.editSheet({
                action: "deleteTableStyle",
                name: original,
                replacement,
              });
              choose("");
            });
        }}
      >
        {t.deleteTableStyle}
      </button>
    </fieldset>
  );
}
