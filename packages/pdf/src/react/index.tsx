import type { PdfEditor } from "../web/index.js";
import { mountProduct } from "@open-document/ui";
import { Navigation } from "@open-document/ui/panels";
import type { Product } from "@open-document/ui/types";
import { prepareFile } from "./file.js";
import { FormatCommands, Properties, PageList } from "./panels.js";
import type { EditorOptions, MountedEditor } from "./types.js";
export type * from "./types.js";
export async function mountEditor(
  container: HTMLElement,
  options: EditorOptions,
): Promise<MountedEditor> {
  const product: Product<PdfEditor> = {
    format: "pdf",
    canCreate: true,
    delimited: false,
    accept: ".pdf",
    readLabel: true,
    extraTabs: true,
    addressStatus: false,
    editReadOnly: true,
    outputs: [
      { kind: "png", label: "exportPagePng" },
      { kind: "jpeg", label: "exportPageJpeg" },
      { kind: "images", label: "exportPageImages" },
      { kind: "jpegs", label: "exportPageJpegs" },
    ],
    prepare: (document, parent, signal) =>
      prepareFile(options, document, parent, signal),
    render(slot, props) {
      if (["edit", "view", "pages", "annotations"].includes(slot))
        return <FormatCommands {...props} tab={slot} />;
      if (slot === "properties")
        return <Properties key={props.state.document?.documentId} {...props} />;
      if (slot === "navigation") return <Navigation {...props} />;
      if (slot === "pages-list") return <PageList {...props} />;
      return null;
    },
  };
  const mounted = await mountProduct(container, options, product);
  return {
    ...mounted,
    format: "pdf",
    get editor() {
      return mounted.editor;
    },
  };
}
