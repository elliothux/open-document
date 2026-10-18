import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxBorderSide,
  DocxBorderPatch,
  DocxCellBorders,
  DocxTableBorders,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

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
  const [scope, setScope] = useState<"cellBorders" | "tableBorders">(
      "cellBorders",
    ),
    [side, setSide] = useState<DocxBorderSide | "all">("all"),
    [width, setWidth] = useState("0.5"),
    [color, setColor] = useState("#000000");
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
              width: kind === "clear" ? 0 : Number(width),
              color: color.slice(1),
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
            return `${labels[side]}: ${value ? `${value.width} pt #${value.color}` : t.mixed}`;
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
          {t.textColor}
          <input
            type="color"
            value={color}
            onChange={(event) => setColor(event.currentTarget.value)}
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
