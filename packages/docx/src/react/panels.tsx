export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import { DocxFormatCommands, DocxProperties } from "./docx-format.js";
export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab } = props;
  if (file.format === "docx" && tab === "edit")
    return (
      <DocxFormatCommands
        key={file.editor.getSnapshot().documentId}
        controller={controller}
        state={state}
        editor={file.editor}
        disabled={disabled}
      />
    );
  return null;
}
export function Properties(props: PanelProps) {
  if (props.file.format === "docx")
    return (
      <DocxProperties
        key={props.file.editor.getSnapshot().documentId}
        controller={props.controller}
        state={props.state}
        editor={props.file.editor}
        disabled={props.disabled}
      />
    );
  return null;
}
