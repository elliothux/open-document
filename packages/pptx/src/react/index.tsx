import type { PresentationEditor } from "../web/index.js";
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
  const product: Product<PresentationEditor> = {
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
    format: "pptx",
    get editor() {
      return mounted.editor;
    },
  };
}
