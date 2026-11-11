import type { PresentationEditor } from "../web/index.js";
import { mountProduct, ProductEditor } from "@open-document/ui";
import { Navigation } from "@open-document/ui/panels";
import { messages } from "@open-document/ui/messages";
import type { EditorEvents, Product } from "@open-document/ui/types";
import { prepareFile } from "./file.js";
import {
  FormatCommands,
  Properties,
  pptxTabs,
  pptxContextActions,
} from "./panels.js";
import { PptxSlideList } from "./pptx-slides.js";
import { PptxNotesBar } from "./pptx-page.js";
import { PptxPresent } from "./pptx-show.js";
import { pptxTextToggles } from "./pptx-format.js";
import type { EditorOptions, MountedEditor } from "./types.js";
export type * from "./types.js";
function product(
  options: EditorOptions,
): Product<PresentationEditor> & { format: "pptx" } {
  return {
    format: "pptx",
    canCreate: true,
    delimited: false,
    accept: ".pptx",
    readLabel: false,
    extraTabs: false,
    addressStatus: false,
    editReadOnly: false,
    outputs: [
      { kind: "pdf", label: "exportAll" },
      { kind: "pdf-current", label: "exportCurrent" },
      { kind: "png", label: "exportPng" },
      { kind: "images", label: "exportSlideImages" },
      { kind: "jpeg", label: "exportJpeg" },
      { kind: "jpegs", label: "exportSlideJpegs" },
    ],
    prepare: (document, parent, signal, locale) =>
      prepareFile({ ...options, locale }, document, parent, signal),
    commands({ state, file, disabled }) {
      const t = messages(state.locale);
      const { editor } = file;
      const format = editor.query.formatting;
      const reason =
        state.mode === "view"
          ? t.viewOnly
          : format.reason ||
            (disabled || state.saving || state.document?.busy
              ? t.commandUnavailable
              : "");
      return pptxTextToggles.map((id) => ({
        id,
        label: t[id],
        ...(id === "strike"
          ? { icon: "strikethrough" }
          : { icon: id, shortcut: id[0]!.toUpperCase() }),
        pressed: format[id] ?? "mixed",
        ...(reason ? { disabledReason: reason } : {}),
        run: (verify) =>
          editor.editObjects(
            { action: "textFormat", format: { [id]: format[id] !== true } },
            verify,
          ),
      }));
    },
    selectionKey: (editor) =>
      JSON.stringify(editor.getSnapshot().data.selection),
    tabs: pptxTabs,
    contextActions: pptxContextActions,
    render(slot, props) {
      if (pptxTabs(props).some((tab) => tab.id === slot))
        return <FormatCommands {...props} tab={slot} />;
      if (slot === "properties")
        return <Properties key={props.state.document?.documentId} {...props} />;
      if (slot === "navigation") return <Navigation {...props} />;
      if (slot === "pages-list") return <PptxSlideList {...props} />;
      if (slot === "below-surface") return <PptxNotesBar {...props} />;
      if (slot === "actions") return <PptxPresent {...props} />;
      return null;
    },
  };
}

export type PptxEditorProps = EditorOptions & EditorEvents<MountedEditor>;

export function PptxEditor({
  onReady,
  onChange,
  onError,
  ...options
}: PptxEditorProps) {
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
