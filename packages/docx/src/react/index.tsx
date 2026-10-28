import type { DocumentEditor } from "../web/index.js";
import { mountProduct } from "@open-document/ui";
import { Navigation } from "@open-document/ui/panels";
import type { Product } from "@open-document/ui/types";
import { prepareFile } from "./file.js";
import { FormatCommands, Properties } from "./panels.js";
import type { EditorOptions, MountedEditor } from "./types.js";
export type * from "./types.js";
import { DocxRuler } from "./docx-ruler.js";
export async function mountEditor(
  container: HTMLElement,
  options: EditorOptions,
): Promise<MountedEditor> {
  const product: Product<DocumentEditor> = {
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
    prepare: (document, parent, signal) =>
      prepareFile(options, document, parent, signal),
    render(slot, props) {
      if (["edit", "view", "pages", "annotations"].includes(slot))
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
  const mounted = await mountProduct(container, options, product);
  return {
    ...mounted,
    format: "docx",
    get editor() {
      return mounted.editor;
    },
  };
}
