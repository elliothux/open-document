import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxBorderSide,
  DocxBorderStyle,
  DocxBorderEdit,
  DocxBorderPatch,
  DocxCellBorders,
  DocxTableBorders,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { borderThemeOptions } from "./docx-border-themes.js";

export function DocxBorders({
  controller,
  state,
  editor,
  cell,
  table,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  cell: DocxCellBorders;
  table?: DocxTableBorders;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const themes = borderThemeOptions(t);
  const styles = [
    ["single", t.pageBorderSingle],
    ["double", t.pageBorderDouble],
    ["dashed", t.dashRegular],
    ["dotted", t.dashDotted],
    ["dashSmallGap", t.tableBorderSmallDash],
    ["dotDash", t.dashDot],
    ["dotDotDash", t.tableBorderDotDotDash],
  ] as const;
  const [scope, setScope] = useState<"cellBorders" | "tableBorders">(
      "cellBorders",
    ),
    [side, setSide] = useState<DocxBorderSide | "all">("all"),
    [style, setStyle] = useState<DocxBorderStyle["style"]>("single"),
    [width, setWidth] = useState("0.5"),
    [color, setColor] = useState("#000000"),
    [themeColor, setThemeColor] = useState<DocxBorderEdit["themeColor"]>(null);
  const values: DocxBorderPatch =
    scope === "tableBorders" && table ? table : cell;
  const sides: DocxBorderSide[] = [
    "top",
    "right",
    "bottom",
    "left",
    ...(scope === "tableBorders" ? (["insideH", "insideV"] as const) : []),
  ];
  const selected =
    side === "all" ? sides : sides.filter((value) => value === side);
  const apply = (kind: "set" | "clear" | "inherit") => {
    const value: DocxBorderPatch = {};
    for (const side of selected)
      value[side] =
        kind === "inherit"
          ? null
          : {
              style: kind === "clear" ? "single" : style,
              width: kind === "clear" ? 0 : Number(width),
              color: color.slice(1),
              ...(kind === "set" && themeColor ? { themeColor } : {}),
            };
    controller.run(() => editor.editTable({ action: scope, value }));
  };
  const labels = {
    top: t.topCellBorder,
    right: t.rightCellBorder,
    bottom: t.bottomCellBorder,
    left: t.leftCellBorder,
    insideH: t.insideHorizontalBorder,
    insideV: t.insideVerticalBorder,
  };
  return (
    <fieldset disabled={disabled}>
      <legend>{table ? t.tableBorders : t.cellBorders}</legend>
      {table && (
        <label>
          {t.borderTarget}
          <select
            aria-label={t.borderTarget}
            value={scope}
            onChange={(event) => {
              if (
                event.currentTarget.value === "tableBorders" ||
                event.currentTarget.value === "cellBorders"
              ) {
                setScope(event.currentTarget.value);
                setSide("all");
              }
            }}
          >
            <option value="cellBorders">{t.cellBorders}</option>
            <option value="tableBorders">{t.tableBorders}</option>
          </select>
        </label>
      )}
      <label>
        {t.borderSide}
        <select
          aria-label={t.borderSide}
          value={side}
          onChange={(event) => {
            const value = event.currentTarget.value;
            const found = sides.find((side) => side === value);
            if (value === "all") setSide("all");
            else if (found) setSide(found);
          }}
        >
          <option value="all">{t.allBorders}</option>
          {sides.map((side) => (
            <option key={side} value={side}>
              {labels[side]}
            </option>
          ))}
        </select>
      </label>
      <p>
        {selected
          .map((side) => {
            const value = values[side];
            return `${labels[side]}: ${value ? `${styles.find(([style]) => style === value.style)![1]} ${value.width} pt #${value.color}` : t.mixed}`;
          })
          .join("; ")}
      </p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          apply("set");
        }}
      >
        <label>
          {t.pageBorderStyle}
          <select
            aria-label={t.pageBorderStyle}
            value={style}
            onChange={(event) => {
              const next = styles.find(
                ([value]) => value === event.currentTarget.value,
              );
              if (next) setStyle(next[0]);
            }}
          >
            {styles.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.shapeLineWidth}
          <input
            type="number"
            min={0.25}
            max={12}
            step={0.125}
            required
            value={width}
            onChange={(event) => setWidth(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.themeColorSlot}
          <select
            value={themeColor ?? ""}
            onChange={(event) =>
              setThemeColor(
                themes.find(
                  ([slot]) => (slot ?? "") === event.currentTarget.value,
                )?.[0] ?? null,
              )
            }
          >
            {themes.map(([slot, label]) => (
              <option key={slot ?? ""} value={slot ?? ""}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.textColor}
          <input
            type="color"
            value={color}
            onChange={(event) => {
              setColor(event.currentTarget.value);
              setThemeColor(null);
            }}
          />
        </label>
        <button
          type="submit"
          aria-label={`${t.apply} ${table ? t.tableBorders : t.cellBorders}`}
        >
          {t.apply}
        </button>
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => apply("clear")}
        >
          {t.noTableBorder}
        </button>
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => apply("inherit")}
        >
          {t.inheritStyleProperty}
        </button>
      </form>
    </fieldset>
  );
}
