import type { FoundationClient } from "./foundation.js";
import type {
  CharacterFormatPatch,
  ParagraphFormatPatch,
  DocxListEdit,
  DocxListLevelUpdate,
  DocxThemeSlot,
  DocxThemeFontEdit,
  DocxStyleUpdate,
  DocxStyleCreation,
  CopiedFormat,
  EditState,
  DocxSelection,
} from "../core/foundation.js";
/** Formatting shares the editor's current selection, grouping and history barriers. */
export function createDocumentFormatting(
  client: FoundationClient,
  profile: Record<string, string>,
  host: {
    state(): EditState;
    selection(): DocxSelection;
    endGroup(): void;
    read<T>(operation: () => Promise<T>): Promise<T>;
    write<T>(operation: () => Promise<T>): Promise<T>;
    edit(operation: () => Promise<EditState>): Promise<void>;
    changed(state: EditState): Promise<void>;
  },
) {
  const apply = (format: () => CopiedFormat) =>
    host.edit(() =>
      client.execute({
        operation: "applyFormat",
        revision: host.state().revision,
        selection: host.selection(),
        format: format(),
        profile,
      }),
    );
  const commands = {
    toggleCharacterFormat(
      key: "bold" | "italic" | "underline" | "strike",
      verify?: () => void,
    ): Promise<void> {
      return apply(() => {
        verify?.();
        const current = host.state().formatting?.character[key];
        return {
          character: { [key]: !(current?.kind === "value" && current.value) },
          paragraph: {},
        };
      });
    },
    setCharacterFormat(
      format: CharacterFormatPatch,
      verify?: () => void,
    ): Promise<void> {
      return apply(() => {
        verify?.();
        return { character: format, paragraph: {} };
      });
    },
    setHyperlink(target: string | null, text?: string): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setHyperlink",
          revision: host.state().revision,
          selection: host.selection(),
          target: target,
          text: text,
        }),
      );
    },
    setParagraphFormat(
      format: ParagraphFormatPatch,
      verify?: () => void,
    ): Promise<void> {
      return apply(() => {
        verify?.();
        return { character: {}, paragraph: format };
      });
    },
    setDefaultTabStop(interval: number | null): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setDefaultTabStop",
          revision: host.state().revision,
          interval: interval,
        }),
      );
    },

    lists() {
      return host.read(() =>
        client.execute({
          operation: "lists",
          revision: host.state().revision,
        }),
      );
    },
    updateListLevel(
      id: number,
      level: number,
      definition: DocxListLevelUpdate,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "updateListLevel",
          revision: host.state().revision,
          id: id,
          level: level,
          definition: definition,
        }),
      );
    },
    editList(change: DocxListEdit): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editList",
          revision: host.state().revision,
          selection: host.selection(),
          change: change,
        }),
      );
    },
    themeColors() {
      return host.read(() =>
        client.execute({
          operation: "themeColors",
          revision: host.state().revision,
        }),
      );
    },
    themeFonts() {
      return host.read(() =>
        client.execute({
          operation: "themeFonts",
          revision: host.state().revision,
        }),
      );
    },
    setThemeFonts(fonts: DocxThemeFontEdit[]): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setThemeFonts",
          revision: host.state().revision,
          fonts: fonts,
          profile: profile,
        }),
      );
    },
    setThemeColor(slot: DocxThemeSlot, color: string): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setThemeColor",
          revision: host.state().revision,
          slot: slot,
          color: color,
        }),
      );
    },
    styles(kind: "paragraph" | "character") {
      return host.read(() =>
        client.execute({
          operation: "styles",
          revision: host.state().revision,
          kind: kind,
        }),
      );
    },
    updateStyle(key: string, format: DocxStyleUpdate): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "updateStyle",
          revision: host.state().revision,
          key: key,
          format: format,
        }),
      );
    },
    createStyle(style: DocxStyleCreation): Promise<string> {
      host.endGroup();
      return host.write(async () => {
        const result = await client.execute({
          operation: "createStyle",
          revision: host.state().revision,
          style: style,
        });
        await host.changed(result.state);
        return result.id;
      });
    },
    deleteStyle(key: string, replacement: string): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "deleteStyle",
          revision: host.state().revision,
          key: key,
          replacement: replacement,
        }),
      );
    },
    captureFormat(): Promise<CopiedFormat> {
      host.endGroup();
      return host.read(() =>
        client.execute({
          operation: "captureFormat",
          revision: host.state().revision,
          selection: host.selection(),
        }),
      );
    },
    applyFormat(format: CopiedFormat): Promise<void> {
      return apply(() => format);
    },
  };
  return commands;
}
