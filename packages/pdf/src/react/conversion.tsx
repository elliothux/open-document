import { useLayoutEffect, useState } from "react";
import { Command, Group } from "@open-document/ui/controls";
import { downloadBytes } from "@open-document/web-core/download";
import type { PdfOfficeConversion } from "../core/pdf.js";
import type { PanelProps } from "./context.js";

export function ConversionCommands({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const editor = file.editor;
  const chinese = state.locale === "zh-CN";
  const revision = state.document?.revision ?? 0;
  const [format, setFormat] = useState<"docx" | "xlsx" | "pptx">("docx");
  const [preview, setPreview] = useState<PdfOfficeConversion>();
  const [accepted, setAccepted] = useState(false);
  useLayoutEffect(() => {
    setPreview(undefined);
    setAccepted(false);
  }, [revision, format]);
  return (
    <Group
      label={chinese ? "转换为可编辑 Office" : "Convert to editable Office"}
    >
      <label>
        {chinese ? "目标格式" : "Target format"}
        <select
          value={format}
          disabled={disabled}
          onChange={(event) =>
            setFormat(event.currentTarget.value as typeof format)
          }
        >
          <option value="docx">DOCX</option>
          <option value="xlsx">XLSX</option>
          <option value="pptx">PPTX</option>
        </select>
      </label>
      <p role="note">
        {chinese
          ? "转换全部页面。扫描页需要先进行 OCR；版式及字体可能变化。"
          : "Converts all pages. Scanned pages require OCR; layout and fonts may change."}
      </p>
      <Command
        label={chinese ? "分析转换" : "Review conversion"}
        disabled={disabled || !!state.document?.draft}
        action={() =>
          controller.run(async () => {
            setAccepted(false);
            setPreview(await editor.convertOffice(format));
          })
        }
      />
      {preview && (
        <>
          {preview.reason && <p role="status">{preview.reason}</p>}
          {preview.warnings.length > 0 && (
            <ul>
              {preview.warnings.map((warning) => (
                <li key={warning}>{warning}</li>
              ))}
            </ul>
          )}
          {preview.status !== "failed" && (
            <>
              <label>
                <input
                  type="checkbox"
                  checked={accepted}
                  onChange={(event) => setAccepted(event.currentTarget.checked)}
                />
                {chinese
                  ? "我接受以上转换损失"
                  : "I accept the conversion losses above"}
              </label>
              <Command
                label={chinese ? "转换并下载" : "Convert and download"}
                disabled={
                  disabled ||
                  !accepted ||
                  preview.revision !== revision ||
                  !!state.document?.draft
                }
                action={() =>
                  controller.run(async () => {
                    const result = await editor.convertOffice(format, true);
                    setPreview(result);
                    if (!result.output) return;
                    const type = {
                      docx: "wordprocessingml.document",
                      xlsx: "spreadsheetml.sheet",
                      pptx: "presentationml.presentation",
                    }[format];
                    downloadBytes(
                      result.output.bytes,
                      `application/vnd.openxmlformats-officedocument.${type}`,
                      `converted.${format}`,
                    );
                    editor.markDownloaded(result.output);
                  })
                }
              />
            </>
          )}
        </>
      )}
    </Group>
  );
}
