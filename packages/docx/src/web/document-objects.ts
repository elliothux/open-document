import type { DocumentHost } from "./document-host.js";
import type { FoundationClient } from "./foundation.js";
import { checkInkTool } from "../core/foundation.js";
import type {
  DocxInkTool,
  DocxCharts,
  DocxChartValue,
  DocxChartUpdate,
  DocxMathFractions,
  DocxMathExpressions,
  DocxMathValue,
  DocxFractionValue,
  DocxMathScripts,
  DocxScriptValue,
  DocxShapeEdit,
  DocxPictureEdit,
} from "../core/foundation.js";
export type DocumentCharts = DocxCharts & { documentId: string };
export type DocumentMathFractions = DocxMathFractions & { documentId: string };
export type DocumentMathExpressions = DocxMathExpressions & {
  documentId: string;
};
export type DocumentMathScripts = DocxMathScripts & { documentId: string };
export function createDocumentObjects(
  client: FoundationClient,
  profile: Record<string, string>,
  host: DocumentHost,
) {
  let inkOptions: DocxInkTool = { tool: "select", color: "174CA0", width: 2 };
  return {
    get inkOptions(): DocxInkTool {
      return inkOptions;
    },
    setInkTool(options: DocxInkTool): Promise<void> {
      checkInkTool(options);
      const value = { ...options };
      return host.edit(async () => {
        inkOptions = value;
        return client.execute({ operation: "editState" });
      });
    },
    charts(): Promise<DocumentCharts> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "charts",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    insertChart(value: DocxChartValue): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editChart",
          revision: host.snapshot().revision,
          chart: { ...value, action: "insert" },
          profile: profile,
        }),
      );
    },
    editChart(
      source: DocumentCharts,
      id: number,
      value: DocxChartUpdate | null,
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot(),
          item = source.items.find((item) => item.id === id);
        const reason =
          value === null
            ? item?.deleteReason
            : "action" in value
              ? value.action === "position"
                ? item?.positionReason
                : item?.sizeReason
              : item?.reason;
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          !item ||
          reason
        )
          throw new Error(reason || "Chart catalog is stale");
        return client.execute({
          operation: "editChart",
          revision: source.revision,
          chart:
            value === null
              ? { action: "delete", id }
              : "action" in value
                ? { ...value, id }
                : { ...value, action: "update", id },
          profile: profile,
        });
      });
    },
    mathExpressions(): Promise<DocumentMathExpressions> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "mathExpressions",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    insertMath(value: DocxMathValue, display = false): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editMath",
          revision: host.snapshot().revision,
          math: { ...value, action: "insert", display },
          profile: profile,
        }),
      );
    },
    editMath(
      source: DocumentMathExpressions,
      id: number,
      value: DocxMathValue | null,
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot(),
          item = source.items.find((item) => item.id === id);
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          !item ||
          item.reason
        )
          throw new Error(item?.reason || "Math catalog is stale");
        return client.execute({
          operation: "editMath",
          revision: source.revision,
          math:
            value === null
              ? { action: "delete", id }
              : { ...value, action: "update", id },
          profile: profile,
        });
      });
    },
    mathScripts(): Promise<DocumentMathScripts> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "mathScripts",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    insertMathScript(value: DocxScriptValue): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editMathScript",
          revision: host.snapshot().revision,
          script: { ...value, action: "insert" },
          profile: profile,
        }),
      );
    },
    editMathScript(
      source: DocumentMathScripts,
      id: number,
      value: DocxScriptValue | null,
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot(),
          item = source.items.find((item) => item.id === id);
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          !item ||
          item.reason
        )
          throw new Error(item?.reason || "Script catalog is stale");
        return client.execute({
          operation: "editMathScript",
          revision: source.revision,
          script:
            value === null
              ? { action: "delete", id }
              : { ...value, action: "update", id },
          profile: profile,
        });
      });
    },
    mathFractions(): Promise<DocumentMathFractions> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "mathFractions",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    insertMathFraction(value: DocxFractionValue): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editMathFraction",
          revision: host.snapshot().revision,
          fraction: { ...value, action: "insert" },
          profile: profile,
        }),
      );
    },
    editMathFraction(
      source: DocumentMathFractions,
      id: number,
      value: DocxFractionValue | null,
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot(),
          item = source.items.find((item) => item.id === id);
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          !item ||
          item.reason
        )
          throw new Error(item?.reason || "Fraction catalog is stale");
        return client.execute({
          operation: "editMathFraction",
          revision: source.revision,
          fraction:
            value === null
              ? { action: "delete", id }
              : { ...value, action: "update", id },
          profile: profile,
        });
      });
    },
    shapes() {
      return host.read(() =>
        client.execute({
          operation: "shapes",
          revision: host.snapshot().revision,
        }),
      );
    },
    editShape(revision: number, shape: DocxShapeEdit): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editShape",
          revision: revision,
          shape: shape,
          profile: profile,
        }),
      );
    },
    pictures() {
      return host.read(() =>
        client.execute({
          operation: "pictures",
          revision: host.snapshot().revision,
        }),
      );
    },
    editPicture(revision: number, picture: DocxPictureEdit): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editPicture",
          revision: revision,
          picture: picture,
          profile: profile,
        }),
      );
    },
  };
}
