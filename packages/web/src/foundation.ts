import { Connection } from "./connection.js";
import {
  docxFlow,
  pageLayout,
  type DocxFlow,
  type PageLayout,
} from "@open-document/wasm/preview";
import {
  docxQuery,
  shapeBatch,
  resourceBudget,
  editState,
  docxHit,
  docxSelectionGeometry,
  docxNavigation,
  type DocxNavigation,
  type NavigationDirection,
  type DocxSelectionGeometry,
  type DocxHit,
  type DocxPosition,
  type EditState,
  type DocxSelection,
  type Budget,
  type DocxQuery,
  type ShapeBatch,
} from "@open-document/wasm/foundation";

/** Text shaping, bounded DOCX operations and preview/PDF, owned by one Worker. */
export class FoundationClient {
  private constructor(private readonly connection: Connection) {}

  static async open(
    wasm: ArrayBuffer,
    workerUrl: URL,
  ): Promise<FoundationClient> {
    const client = new FoundationClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.request({ operation: "openFoundation", wasm });
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  async defaultBudget(): Promise<Budget> {
    return resourceBudget(
      await this.connection.request({ operation: "budget" }),
    );
  }
  async shape(text: string, size = 32, language = "und"): Promise<ShapeBatch> {
    return shapeBatch(
      await this.connection.request({
        operation: "shape",
        text,
        size,
        language,
      }),
    );
  }
  async openDocx(bytes: Uint8Array, budget: Budget): Promise<DocxQuery> {
    return docxQuery(
      await this.connection.request({ operation: "openDocx", bytes, budget }),
    );
  }
  async query(): Promise<DocxQuery> {
    return docxQuery(await this.connection.request({ operation: "query" }));
  }
  async editState(): Promise<EditState> {
    return editState(await this.connection.request({ operation: "editState" }));
  }

  async beginComposition(revision: number): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "beginComposition",
        revision,
      }),
    );
  }

  async updateComposition(
    revision: number,
    compositionId: number,
    text: string,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "updateComposition",
        revision,
        compositionId,
        text,
      }),
    );
  }

  async commitComposition(
    revision: number,
    compositionId: number,
    text: string,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "commitComposition",
        revision,
        compositionId,
        text,
      }),
    );
  }

  async cancelComposition(
    revision: number,
    compositionId: number,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "cancelComposition",
        revision,
        compositionId,
      }),
    );
  }
  async selectDocx(
    revision: number,
    selection: DocxSelection,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "selectDocx",
        revision,
        selection,
      }),
    );
  }
  async replaceRange(
    revision: number,
    selection: DocxSelection,
    text: string,
    inputGroup?: number,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "replaceRange",
        revision,
        selection,
        text,
        inputGroup,
      }),
    );
  }
  async selectedText(
    revision: number,
    selection: DocxSelection,
  ): Promise<string> {
    const result = await this.connection.request({
      operation: "selectedText",
      revision,
      selection,
    });
    if (typeof result !== "string")
      throw new Error("Invalid selection text returned by Wasm");
    return result;
  }
  async undoDocx(revision: number): Promise<EditState> {
    return editState(
      await this.connection.request({ operation: "undoDocx", revision }),
    );
  }

  async deleteDocx(
    revision: number,
    direction: "backward" | "forward",
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "deleteDocx",
        revision,
        direction,
      }),
    );
  }
  async redoDocx(revision: number): Promise<EditState> {
    return editState(
      await this.connection.request({ operation: "redoDocx", revision }),
    );
  }
  async replaceNode(
    node: number,
    revision: number,
    text: string,
  ): Promise<number> {
    const result = await this.connection.request({
      operation: "replaceNode",
      node,
      revision,
      text,
    });
    if (typeof result !== "number")
      throw new Error("Invalid revision response");
    return result;
  }
  async saveDocx(): Promise<Uint8Array> {
    const result = await this.connection.request({ operation: "saveDocx" });
    if (!(result instanceof Uint8Array))
      throw new Error("Invalid byte response");
    return result;
  }
  async flow(): Promise<DocxFlow> {
    return docxFlow(await this.connection.request({ operation: "flow" }));
  }
  async layout(profile: Record<string, string>): Promise<PageLayout> {
    return pageLayout(
      await this.connection.request({ operation: "layout", profile }),
    );
  }

  async hitTest(
    layoutId: number,
    page: number,
    x: number,
    y: number,
  ): Promise<DocxHit> {
    return docxHit(
      await this.connection.request({
        operation: "hitTest",
        layoutId,
        page,
        x,
        y,
      }),
    );
  }

  async caret(layoutId: number, position: DocxPosition): Promise<DocxHit> {
    return docxHit(
      await this.connection.request({ operation: "caret", layoutId, position }),
    );
  }
  async exportPdf(outputBytes: number, layoutId?: number): Promise<Uint8Array> {
    const result = await this.connection.request({
      operation: "exportPdf",
      outputBytes,
      layoutId,
    });
    if (!(result instanceof Uint8Array)) throw new Error("Invalid PDF bytes");
    return result;
  }
  async navigateDocx(
    revision: number,
    layoutId: number,
    direction: NavigationDirection,
    extend = false,
  ): Promise<DocxNavigation> {
    return docxNavigation(
      await this.connection.request({
        operation: "navigateDocx",
        revision,
        layoutId,
        direction,
        extend,
      }),
    );
  }

  async selectionGeometry(
    layoutId: number,
    selection: DocxSelection,
  ): Promise<DocxSelectionGeometry> {
    return docxSelectionGeometry(
      await this.connection.request({
        operation: "selectionGeometry",
        layoutId,
        selection,
      }),
    );
  }

  async imageBytes(key: string): Promise<Uint8Array> {
    const result = await this.connection.request({
      operation: "imageBytes",
      key,
    });
    if (!(result instanceof Uint8Array)) throw new Error("Invalid image bytes");
    return result;
  }
  async addImage(
    key: string,
    width: number,
    height: number,
    bytes: Uint8Array,
  ): Promise<string> {
    const result = await this.connection.request({
      operation: "image",
      key,
      width,
      height,
      bytes,
    });
    if (typeof result !== "string" || !result)
      throw new Error("Invalid image resource identity");
    return result;
  }
  dispose(): void {
    this.connection.dispose();
  }
}
