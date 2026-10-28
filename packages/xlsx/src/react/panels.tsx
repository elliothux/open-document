export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import { Command, Group } from "@open-document/ui/controls";
import { Navigation } from "@open-document/ui/panels";
import { messages } from "@open-document/ui/messages";
import { XlsxSheets, XlsxFrozen, XlsxView } from "./xlsx-sheets.js";
import { XlsxOutlinePanel } from "./xlsx-outline.js";
import { XlsxTablesPanel } from "./xlsx-tables.js";
import { XlsxPivotsPanel } from "./xlsx-pivot.js";
import { XlsxNames } from "./xlsx-names.js";
import { XlsxFormat } from "./xlsx-format.js";
import { XlsxSearch } from "./xlsx-search.js";
import { XlsxSort } from "./xlsx-sort.js";
import { XlsxDataTools } from "./xlsx-data-tools.js";
import { XlsxFilter } from "./xlsx-filter.js";
import { XlsxPrintSetup, XlsxPrintCommands } from "./xlsx-print-setup.js";
export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab } = props;
  const t = messages(state.locale);
  if (file.format === "xlsx") {
    return (
      <>
        {tab === "edit" && (
          <>
            <Group label={t.edit}>
              <Command
                label={t.clear}
                disabled={disabled}
                action={() => controller.run(() => file.editor.clear())}
              />
              <Command
                label={t.clearFormats}
                disabled={disabled}
                action={() =>
                  controller.run(() => file.editor.clear("formats"))
                }
              />
              <Command
                label={t.clearAll}
                disabled={disabled}
                action={() => controller.run(() => file.editor.clear("all"))}
              />
            </Group>
          </>
        )}
        {tab === "view" && (
          <XlsxPrintCommands
            controller={controller}
            state={state}
            editor={file.editor}
            disabled={disabled}
            navigation={<Navigation {...props} />}
          />
        )}
      </>
    );
  }
  return null;
}
export function Properties(props: PanelProps) {
  if (props.file.format === "xlsx")
    return (
      <aside className="od-properties">
        <XlsxTablesPanel
          key={`tables:${props.state.document?.documentId}:${props.file.editor.currentState.sheet}`}
          {...props}
          disabled={props.disabled || !!props.state.document?.stopped}
        />
        <XlsxOutlinePanel
          {...props}
          disabled={props.disabled || !!props.state.document?.stopped}
        />
        <XlsxSearch
          key={props.state.document?.documentId}
          controller={props.controller}
          state={props.state}
          editor={props.file.editor}
          disabled={props.disabled}
        />
        <XlsxFilter
          key={`filter:${props.state.document?.documentId}:${props.file.editor.currentState.sheet}`}
          controller={props.controller}
          state={props.state}
          editor={props.file.editor}
          disabled={props.disabled || !!props.state.document?.stopped}
        />
        <XlsxSort
          key={`${props.state.document?.documentId}:${props.file.editor.currentState.sheet}:${props.file.editor.currentState.selection.address}`}
          controller={props.controller}
          state={props.state}
          editor={props.file.editor}
          disabled={props.disabled || !!props.state.document?.stopped}
        />
        <XlsxDataTools
          controller={props.controller}
          state={props.state}
          editor={props.file.editor}
          disabled={props.disabled || !!props.state.document?.stopped}
        />
        <XlsxPivotsPanel
          key={`pivots:${props.state.document?.documentId}:${props.file.editor.currentState.sheet}`}
          {...props}
          editor={props.file.editor}
        />
        <XlsxFormat
          controller={props.controller}
          state={props.state}
          editor={props.file.editor}
          disabled={props.disabled || !!props.state.document?.stopped}
        />
        <XlsxPrintSetup
          key={`${props.state.document?.documentId}:${props.file.editor.currentState.sheet}:${JSON.stringify([props.file.editor.currentState.printSetup, props.file.editor.currentState.printRange, props.file.editor.currentState.headerFooter])}`}
          controller={props.controller}
          state={props.state}
          editor={props.file.editor}
          disabled={props.disabled}
        />
        <div
          onMouseDown={(event) => {
            if (
              event.button === 0 &&
              event.target instanceof Element &&
              event.target.closest("button")
            )
              event.preventDefault();
          }}
        >
          <XlsxView
            controller={props.controller}
            state={props.state}
            editor={props.file.editor}
            disabled={props.disabled || !!props.state.document?.stopped}
          />
          <XlsxNames
            key={`${props.state.document?.documentId}:${JSON.stringify(props.file.editor.currentState.names)}`}
            controller={props.controller}
            state={props.state}
            editor={props.file.editor}
            disabled={props.disabled || !!props.state.document?.stopped}
          />
          <XlsxFrozen
            controller={props.controller}
            state={props.state}
            editor={props.file.editor}
            disabled={props.disabled || !!props.state.document?.stopped}
          />
        </div>
      </aside>
    );
  return null;
}
export function Sheets({ controller, state, file, disabled }: PanelProps) {
  if (file.format !== "xlsx") return null;
  return (
    <XlsxSheets
      key={state.document?.documentId}
      controller={controller}
      state={state}
      editor={file.editor}
      disabled={disabled}
    />
  );
}
