import { messages } from "@open-document/ui/messages";
import type { DocumentEditor } from "../web/index.js";
import { mountProduct, ProductEditor } from "@open-document/ui";
import { Navigation } from "@open-document/ui/panels";
import type { EditorEvents, Product } from "@open-document/ui/types";
import { prepareFile } from "./file.js";
import {
  FormatCommands,
  Properties,
  docxTabs,
  docxContextActions,
} from "./panels.js";
import type { EditorOptions, MountedEditor } from "./types.js";
export type * from "./types.js";
import { DocxRuler } from "./docx-ruler.js";
function product(
  options: EditorOptions,
): Product<DocumentEditor> & { format: "docx" } {
  return {
    format: "docx",
    canCreate: true,
    delimited: false,
    accept: ".docx",
    readLabel: false,
    extraTabs: false,
    addressStatus: false,
    editReadOnly: true,
    outputs: [
      { kind: "pdf", label: "exportPdf" },
      { kind: "html", label: "exportHtml" },
      {
        kind: "markdown",
        label: "exportMarkdown",
        title: "markdownExportHint",
      },
      { kind: "png", label: "exportPagePng" },
      { kind: "images", label: "exportPageImages" },
    ],
    prepare: (document, parent, signal, locale) =>
      prepareFile({ ...options, locale }, document, parent, signal),
    commands({ file, state, disabled }) {
      const t = messages(state.locale);
      const formatting = file.editor.getSnapshot().data.formatting;
      return (["bold", "italic", "underline", "strike"] as const).map((id) => {
        const current = formatting?.character[id];
        const disabledReason =
          state.mode === "view"
            ? t.viewOnly
            : formatting?.reason ||
              (disabled || !formatting ? t.commandUnavailable : "");
        return {
          id,
          label: t[id],
          ...(id === "strike"
            ? { icon: "strikethrough" }
            : { icon: id, shortcut: id[0]!.toUpperCase() }),
          pressed:
            current?.kind === "mixed"
              ? "mixed"
              : current?.kind === "value" && current.value,
          ...(disabledReason ? { disabledReason } : {}),
          run: (verify) =>
            file.editor.formatting.toggleCharacterFormat(id, verify),
        };
      });
    },
    selectionKey: (editor) =>
      JSON.stringify(editor.getSnapshot().data.selection),
    tabs: docxTabs,
    contextActions: docxContextActions,
    render(slot, props) {
      if (
        [
          "edit",
          "view",
          "insert",
          "layout",
          "references",
          "review",
          "table",
          "picture",
          "header-footer",
        ].includes(slot)
      )
        return <FormatCommands {...props} tab={slot} />;
      if (slot === "properties")
        return <Properties key={props.state.document?.documentId} {...props} />;
      if (slot === "navigation") return <Navigation {...props} />;
      if (slot === "before-surface")
        return (
          <DocxRuler
            key={props.state.document?.documentId}
            {...props}
            editor={props.file.editor}
          />
        );
      return null;
    },
  };
}

export type DocxEditorProps = EditorOptions & EditorEvents<MountedEditor>;

export function DocxEditor({
  onReady,
  onChange,
  onError,
  ...options
}: DocxEditorProps) {
  return (
    <ProductEditor
      product={product}
      options={options}
      onReady={onReady}
      onChange={onChange}
      onError={onError}
    />
  );
}

export function mountEditor(
  container: HTMLElement,
  options: EditorOptions,
): Promise<MountedEditor> {
  return mountProduct(container, options, product);
}
