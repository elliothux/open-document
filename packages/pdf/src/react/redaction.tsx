import { useLayoutEffect, useState } from "react";
import { Command, Group } from "@open-document/ui/controls";
import { downloadBytes } from "@open-document/web-core/download";
import type { PdfRedactionPreview, PdfRedactionRegion } from "../core/pdf.js";
import type { PanelProps } from "./context.js";

/** Redaction candidates are revision-bound and never mark the source as saved. */
export function RedactionPanel({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const editor = file.editor;
  const chinese = state.locale === "zh-CN";
  const revision = state.document?.revision ?? 0;
  const page = editor.snapshot.page;
  const [coordinates, setCoordinates] = useState({
    x: "20",
    y: "20",
    width: "120",
    height: "30",
  });
  const [regions, setRegions] = useState<PdfRedactionRegion[]>([]);
  const [preview, setPreview] = useState<PdfRedactionPreview>();
  const [accepted, setAccepted] = useState(false);
  useLayoutEffect(() => () => editor.clearRedactionPreview(), [editor]);
  useLayoutEffect(() => {
    setPreview(undefined);
    setAccepted(false);
  }, [revision, page]);
  useLayoutEffect(() => {
    setRegions([]);
    setPreview(undefined);
    setAccepted(false);
  }, [state.document?.documentId]);
  const invalidate = () => {
    setPreview(undefined);
    setAccepted(false);
    editor.clearRedactionPreview();
  };
  const ready =
    preview?.revision === revision && !preview.readOnlyReason && accepted;
  return (
    <Group label={chinese ? "真实脱敏副本" : "Redacted copy"}>
      <p role="note">
        {chinese
          ? "原文件和撤销历史仍保留原内容。只有导出的脱敏副本会清理数据；黑色预览框不是已完成脱敏。"
          : "The original file and undo history retain the original content. Only the exported copy is cleaned; a preview box is not applied redaction."}
      </p>
      <div className="flex flex-wrap gap-1">
        {(["x", "y", "width", "height"] as const).map((key, index) => (
          <label key={key}>
            {
              (chinese
                ? ["脱敏横向位置", "脱敏纵向位置", "脱敏宽度", "脱敏高度"]
                : [
                    "Redaction horizontal position",
                    "Redaction vertical position",
                    "Redaction width",
                    "Redaction height",
                  ])[index]
            }
            <input
              type="number"
              value={coordinates[key]}
              min={key === "width" || key === "height" ? "0.01" : "0"}
              disabled={disabled}
              onChange={(event) => {
                const value = event.currentTarget.value;
                setCoordinates((before) => ({ ...before, [key]: value }));
              }}
            />
          </label>
        ))}
      </div>
      <Command
        label={chinese ? "标记当前页区域" : "Mark current page region"}
        disabled={disabled || regions.length >= 4096}
        action={() => {
          invalidate();
          setRegions((before) => [
            ...before,
            {
              page,
              x: Number(coordinates.x),
              y: Number(coordinates.y),
              width: Number(coordinates.width),
              height: Number(coordinates.height),
            },
          ]);
        }}
      />
      <ol>
        {regions.map((region, index) => (
          <li key={`${index}:${region.page}`}>
            {`${region.page}: ${region.x}, ${region.y}, ${region.width} × ${region.height}`}
            <button
              type="button"
              disabled={disabled}
              aria-label={`${chinese ? "移除脱敏区域" : "Remove redaction region"} ${index + 1}`}
              onClick={() => {
                invalidate();
                setRegions((before) =>
                  before.filter((_, position) => position !== index),
                );
              }}
            >
              ×
            </button>
          </li>
        ))}
      </ol>
      <Command
        label={chinese ? "预览实际移除范围" : "Preview actual removal"}
        disabled={disabled || regions.length === 0}
        action={() =>
          controller.run(async () => {
            const result = await editor.previewRedaction(regions);
            setAccepted(false);
            setPreview(result);
          })
        }
      />
      {preview && (
        <div aria-live="polite">
          {preview.readOnlyReason && (
            <p role="alert">{preview.readOnlyReason}</p>
          )}
          {!preview.readOnlyReason && (
            <>
              <p>
                {chinese
                  ? `将移除或清理 ${preview.affected.length} 个对象；文字组、路径和像素的实际范围可能大于标记框。`
                  : `${preview.affected.length} objects will be removed or cleaned; text groups, paths and pixels may extend beyond the marked rectangle.`}
              </p>
              <details>
                <summary>
                  {chinese ? "实际影响对象" : "Affected objects"}
                </summary>
                <ul>
                  {preview.affected.slice(0, 100).map((item, index) => (
                    <li
                      key={index}
                    >{`${item.page} · ${item.kind}: ${item.x.toFixed(2)}, ${item.y.toFixed(2)}, ${item.width.toFixed(2)} × ${item.height.toFixed(2)}`}</li>
                  ))}
                </ul>
              </details>
              <ul>
                {preview.warnings.map((warning) => (
                  <li key={warning}>{warning}</li>
                ))}
              </ul>
              <label>
                <input
                  type="checkbox"
                  checked={accepted}
                  disabled={disabled}
                  onChange={(event) => setAccepted(event.currentTarget.checked)}
                />
                {chinese
                  ? "我已查看移除范围，接受副本中的内容与交互损失"
                  : "I reviewed the removal scope and accept the content and interaction losses in the copy"}
              </label>
            </>
          )}
        </div>
      )}
      <Command
        label={
          chinese ? "应用并导出脱敏副本" : "Apply and export redacted copy"
        }
        disabled={disabled || !ready}
        action={() =>
          controller.run(async () => {
            const result = await editor.exportRedaction(regions);
            downloadBytes(
              result.output.bytes,
              "application/pdf",
              `${state.name.replace(/\.[^.]*$/, "")}-redacted.pdf`,
            );
            editor.markDownloaded(result.output);
          })
        }
      />
      <Command
        label={chinese ? "清除脱敏标记" : "Clear redaction marks"}
        disabled={disabled || regions.length === 0}
        action={() => {
          invalidate();
          setRegions([]);
        }}
      />
    </Group>
  );
}
