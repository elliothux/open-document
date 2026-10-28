import { useState } from "react";
import { Command, Group } from "@open-document/ui/controls";
import type { PanelProps } from "./context.js";

function chosenPages(text: string, ids: readonly string[]): string[] {
  if (!text.trim()) return [...ids];
  const chosen = new Set<string>();
  for (const token of text.split(",")) {
    const part = token.trim();
    if (!/^\d+(?:-\d+)?$/.test(part))
      throw new Error("Use page numbers or ranges, such as 1-3,5");
    const [a, b] = part.split("-");
    const first = Number(a),
      last = b === undefined ? first : Number(b);
    if (first < 1 || last < first || last > ids.length)
      throw new Error("Page range is outside the PDF");
    for (let index = first - 1; index < last; index++) {
      const id = ids[index]!;
      if (chosen.has(id)) throw new Error("Choose each source page once");
      chosen.add(id);
    }
  }
  return [...chosen];
}

/** The core computes all page, content and annotation coordinate transforms. */
export function PageArrangeControls({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const [range, setRange] = useState("");
  const [columns, setColumns] = useState("2"),
    [rows, setRows] = useState("1");
  const [width, setWidth] = useState("595"),
    [height, setHeight] = useState("842");
  const zh = state.locale === "zh-CN",
    editor = file.editor;
  const query = editor.getSnapshot().data.query;
  const blocked =
    disabled || !!state.document?.draft || !!query.pageOrderReason;
  return (
    <Group label={zh ? "页面拼拆" : "Page arrangement"}>
      <Command
        label={zh ? "左右拆成两页" : "Split into left and right pages"}
        disabled={blocked}
        action={() => controller.run(() => editor.splitPageGrid(2, 1))}
      />
      <Command
        label={zh ? "上下拆成两页" : "Split into top and bottom pages"}
        disabled={blocked}
        action={() => controller.run(() => editor.splitPageGrid(1, 2))}
      />
      <details>
        <summary>{zh ? "多页合一" : "N-up pages"}</summary>
        <label>
          {zh ? "源页范围（空白为全部）" : "Source pages (blank means all)"}
          <input
            aria-label={zh ? "拼页源页范围" : "N-up source page range"}
            disabled={blocked}
            maxLength={4096}
            value={range}
            placeholder="1-3,5"
            onChange={(event) => setRange(event.currentTarget.value)}
          />
        </label>
        <label>
          {zh ? "列数" : "Columns"}
          <input
            aria-label={zh ? "拼页列数" : "N-up columns"}
            type="number"
            min={1}
            max={16}
            disabled={blocked}
            value={columns}
            onChange={(event) => setColumns(event.currentTarget.value)}
          />
        </label>
        <label>
          {zh ? "行数" : "Rows"}
          <input
            aria-label={zh ? "拼页行数" : "N-up rows"}
            type="number"
            min={1}
            max={16}
            disabled={blocked}
            value={rows}
            onChange={(event) => setRows(event.currentTarget.value)}
          />
        </label>
        <label>
          {zh ? "纸张宽度（点）" : "Paper width (points)"}
          <input
            aria-label={zh ? "拼页纸张宽度" : "N-up paper width"}
            type="number"
            min={1}
            max={14400}
            disabled={blocked}
            value={width}
            onChange={(event) => setWidth(event.currentTarget.value)}
          />
        </label>
        <label>
          {zh ? "纸张高度（点）" : "Paper height (points)"}
          <input
            aria-label={zh ? "拼页纸张高度" : "N-up paper height"}
            type="number"
            min={1}
            max={14400}
            disabled={blocked}
            value={height}
            onChange={(event) => setHeight(event.currentTarget.value)}
          />
        </label>
        <p>
          {zh
            ? "裁剪和拼拆页保留隐藏源数据，不属于脱敏。跨边界字段或复杂关联会阻止操作。"
            : "Cropping and page arrangement retain hidden source data. Fields crossing boundaries or complex relationships protect the operation."}
        </p>
        <Command
          label={zh ? "应用多页合一" : "Apply N-up"}
          disabled={blocked}
          action={() =>
            controller.run(() =>
              editor.nupPages(
                chosenPages(
                  range,
                  editor.snapshot.pages.map((page) => page.id),
                ),
                Number(columns),
                Number(rows),
                Number(width),
                Number(height),
              ),
            )
          }
        />
      </details>
    </Group>
  );
}
