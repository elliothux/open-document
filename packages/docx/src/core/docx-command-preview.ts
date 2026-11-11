import { type DocxFlow, type LayoutPreparation } from "./preview.js";
import type { ImagePreparation } from "@open-document/wasm/abi/drawing";

import type {
  DocxHit,
  DocxPosition,
  DocxSelectionView,
  DocxSelectionViewRequest,
} from "./docx-hit.js";

import { type NavigationDirection, type DocxNavigation } from "./foundation.js";
import type { DocxRuntime } from "./docx-session.js";
export const docxPreviewCommands = {
  exportMarkup(
    session: DocxRuntime,
    {
      revision,
      format,
      outputBytes = session.inputLimits().exportBytes,
    }: {
      revision: number;
      format: "html" | "markdown";
      outputBytes?: number | undefined;
    },
  ): Uint8Array {
    return session.bytes({
      operation: "exportDocxMarkup",
      revision,
      format,
      outputBytes,
    });
  },
  flow(session: DocxRuntime, _command: object): DocxFlow {
    return session.call<DocxFlow>({ operation: "flow" });
  },
  layout(
    session: DocxRuntime,
    {
      profile,
      prepareImages = false,
      selectionView,
    }: {
      profile: Record<string, string>;
      prepareImages?: boolean | undefined;
      selectionView?: DocxSelectionViewRequest | undefined;
    },
  ): LayoutPreparation {
    return session.call<LayoutPreparation>({
      operation: "layout",
      profile,
      prepareImages,
      selectionView,
    });
  },
  docxSelectionView(
    session: DocxRuntime,
    request: DocxSelectionViewRequest & { layoutId: number },
  ): DocxSelectionView {
    return session.call<DocxSelectionView>({
      ...request,
      operation: "docxSelectionView",
    });
  },
  hitTest(
    session: DocxRuntime,
    {
      layoutId,
      page,
      x,
      y,
    }: { layoutId: number; page: number; x: number; y: number },
  ): DocxHit {
    return session.call<DocxHit>({
      operation: "hitTest",
      layoutId,
      page,
      x,
      y,
    });
  },
  caret(
    session: DocxRuntime,
    { layoutId, position }: { layoutId: number; position: DocxPosition },
  ): DocxHit {
    return session.call<DocxHit>({ operation: "caret", layoutId, position });
  },
  navigateDocx(
    session: DocxRuntime,
    {
      revision,
      layoutId,
      direction,
      extend = false,
      selectionView,
    }: {
      revision: number;
      layoutId: number;
      direction: NavigationDirection;
      extend?: boolean | undefined;
      selectionView?: boolean | undefined;
    },
  ): DocxNavigation {
    return session.call<DocxNavigation>({
      operation: "navigateDocx",
      revision,
      layoutId,
      direction,
      extend,
      selectionView,
    });
  },
  exportPdf(
    session: DocxRuntime,
    {
      outputBytes,
      layoutId,
    }: { outputBytes: number; layoutId?: number | undefined },
  ): Uint8Array {
    return session.bytes({ operation: "exportPdf", outputBytes, layoutId });
  },
  imageBytes(session: DocxRuntime, { key }: { key: string }): Uint8Array {
    return session.bytes({ operation: "imageBytes", key });
  },
  imageSource(session: DocxRuntime, { key }: { key: string }) {
    const image = session.call<ImagePreparation<number>>({
      operation: "imageBytes",
      key,
      header: true,
    });
    return { ...image, bytes: session.outputBytes(image.bytes) };
  },
  imagePixels(session: DocxRuntime, { key }: { key: string }) {
    const { width, height, bytes } = session.call<{
      width: number;
      height: number;
      bytes: number;
    }>({ operation: "imagePixels", key });
    return { width, height, bytes: session.outputBytes(bytes) };
  },
  addImage(
    session: DocxRuntime,
    {
      key,
      width,
      height,
      rgba,
    }: { key: string; width: number; height: number; rgba: Uint8Array },
  ): string {
    return session.call<{ key: string }>({
      operation: "image",
      key,
      width,
      height,
      bytes: rgba,
    }).key;
  },
};
