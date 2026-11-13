import type { PdfEditor as PdfHost } from "../web/index.js";
import { mountProduct, ProductEditor } from "@open-document/ui";
import { Navigation } from "@open-document/ui/panels";
import type { EditorEvents, Product } from "@open-document/ui/types";
import { prepareFile } from "./file.js";
import {
  FormatCommands,
  Properties,
  pdfTabs,
  pdfContextActions,
  pdfFileActions,
} from "./panels.js";
import { PageList } from "./pdf-pages.js";
import type { EditorOptions, MountedEditor } from "./types.js";
export type * from "./types.js";
function product(options: EditorOptions): Product<PdfHost> & { format: "pdf" } {
  return {
    format: "pdf",
    canCreate: true,
    delimited: false,
    accept: ".pdf",
    readLabel: true,
    extraTabs: true,
    addressStatus: false,
    editReadOnly: false,
    outputs: [
      { kind: "png", label: "exportPagePng" },
      { kind: "jpeg", label: "exportPageJpeg" },
      { kind: "images", label: "exportPageImages" },
      { kind: "jpegs", label: "exportPageJpegs" },
    ],
    prepare: (document, parent, signal, locale) =>
      prepareFile({ ...options, locale }, document, parent, signal),
    prepareFile: (file, parent, signal, locale) =>
      prepareFile({ ...options, locale }, file, parent, signal),
    tabs: () => pdfTabs,
    fileActions: pdfFileActions,
    contextActions: pdfContextActions,
    render(slot, props) {
      if (pdfTabs.some((tab) => tab.id === slot))
        return <FormatCommands {...props} tab={slot} />;
      if (slot === "properties")
        return <Properties key={props.state.document?.documentId} {...props} />;
      if (slot === "navigation") return <Navigation {...props} />;
      if (slot === "pages-list") return <PageList {...props} />;
      return null;
    },
  };
}

export type PdfEditorProps = EditorOptions & EditorEvents<MountedEditor>;

export function PdfEditor({
  onReady,
  onChange,
  onError,
  ...options
}: PdfEditorProps) {
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
