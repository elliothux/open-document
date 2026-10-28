import { useLayoutEffect, useState } from "react";
import { Command, Group } from "@open-document/ui/controls";
import type { PdfObject, PdfTextSpec } from "../core/pdf.js";
import type { PdfEditor } from "../web/index.js";
import type { PanelProps } from "./context.js";

export function usePdfObjects(
  editor: PdfEditor,
  revision: number,
  page: string,
) {
  const [objects, setObjects] = useState<PdfObject[]>([]);
  const [error, setError] = useState("");
  useLayoutEffect(() => {
    let active = true;
    void editor.objects().then(
      (result) => {
        if (active && result.revision === revision && result.page === page) {
          setObjects(result.objects);
          setError("");
        }
      },
      (failure: unknown) => {
        if (active) {
          setObjects([]);
          setError(
            failure instanceof Error
              ? failure.message
              : "PDF object query failed",
          );
        }
      },
    );
    return () => {
      active = false;
    };
  }, [editor, revision, page]);
  return { objects, error };
}

export function ImageInput({
  controller,
  state,
  file,
  disabled,
  replace = false,
}: PanelProps & { replace?: boolean }) {
  return (
    <label className="od-command">
      {state.locale === "zh-CN"
        ? replace
          ? "替换图片"
          : "插入图片"
        : replace
          ? "Replace image"
          : "Insert image"}
      <input
        type="file"
        accept="image/png,image/jpeg,image/gif,image/webp"
        disabled={disabled}
        onChange={(event) => {
          const source = event.currentTarget.files?.[0];
          event.currentTarget.value = "";
          if (source)
            controller.run(async () => {
              if (source.size > 16777216)
                throw new Error("PDF image input exceeds budget");
              await file.editor.insertImage(
                new Uint8Array(await source.arrayBuffer()),
                replace,
              );
            });
        }}
      />
    </label>
  );
}

export function ObjectCommands(props: PanelProps) {
  const roles: PdfTextSpec["role"][] = [
    "text",
    "watermark",
    "header",
    "footer",
    "page-number",
  ];
  const labels =
    props.state.locale === "zh-CN"
      ? [
          "插入文字框",
          "水印（全部页）",
          "页眉（全部页）",
          "页脚（全部页）",
          "页码（全部页）",
        ]
      : [
          "Insert text box",
          "Watermark (all pages)",
          "Header (all pages)",
          "Footer (all pages)",
          "Page numbers (all pages)",
        ];
  return (
    <Group label={props.state.locale === "zh-CN" ? "内容" : "Content"}>
      {roles.map((role, index) => (
        <Command
          key={role}
          label={labels[index]!}
          disabled={props.disabled || !!props.state.document?.draft}
          action={() =>
            props.controller.run(() => props.file.editor.beginText(role))
          }
        />
      ))}
      <ImageInput
        {...props}
        disabled={props.disabled || !!props.state.document?.draft}
      />
    </Group>
  );
}
