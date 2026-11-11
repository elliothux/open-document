export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import { Command, Group } from "@open-document/ui/controls";
import {
  EditorCommandButton,
  EditorFontControls,
  EditorPanel,
} from "@open-document/ui";
import { Icon, type IconName } from "@open-document/ui/icons";
import { RibbonActions, RibbonMenu } from "@open-document/ui/ribbon";
import { messages, type MessageKey } from "@open-document/ui/messages";
import type { RibbonTab } from "@open-document/ui/types";
import { XlsxNumberFormat } from "./xlsx-number-format.js";
import { XlsxBorders } from "./xlsx-borders.js";
import {
  XlsxSheetStrip,
  XlsxSheets,
  XlsxFrozen,
  XlsxView,
} from "./xlsx-sheets.js";
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

export const xlsxTabs = [
  { id: "edit", label: "homeTab" },
  { id: "insert", label: "insertTabLabel" },
  { id: "data", label: "dataTab" },
  { id: "review", label: "reviewTab" },
  { id: "view", label: "view", readOnly: true },
] as const satisfies readonly RibbonTab[];

const labels = {
  format: "cellFormat",
  find: "findReplace",
  sheets: "manageSheets",
  dimensions: "dimensions",
  tables: "tableTab",
  sort: "sortCells",
  filter: "filterTask",
  outline: "outlineTask",
  pivots: "pivotTask",
  names: "definedNames",
  validation: "dataValidation",
  print: "sheetPrintSetup",
  view: "worksheetView",
  objects: "objects",
  review: "reviewTab",
} as const satisfies Record<string, MessageKey>;
type Task = keyof typeof labels;
const icons = {
  format: "format-painter",
  find: "search",
  sheets: "file-spreadsheet",
  dimensions: "ruler",
  tables: "table-cells",
  sort: "list-sort",
  filter: "filter",
  outline: "list-nested",
  pivots: "pivot-table",
  names: "name-tag",
  validation: "list-checks",
  print: "printer",
  view: "file-preview",
  objects: "shapes",
  review: "comment-count",
} as const satisfies Record<Task, IconName>;

function action(props: PanelProps, task: Task) {
  const { workspace, state } = props;
  return {
    label: messages(state.locale)[labels[task]],
    icon: icons[task],
    disabled: state.loading,
    pressed: workspace?.task === task,
    run: () => workspace?.showTask(task),
  };
}

export function xlsxContextActions(props: PanelProps) {
  return props.state.mode === "view"
    ? [action(props, "find")]
    : [
        action(props, "format"),
        action(props, "dimensions"),
        action(props, "find"),
      ];
}

export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab, workspace } = props;
  const t = messages(state.locale);
  const { editor } = file;
  if (!workspace) return null;
  const show = (task: Task) => {
    const command = action(props, task);
    return (
      <Command
        key={task}
        label={command.label}
        icon={command.icon}
        disabled={command.disabled}
        pressed={command.pressed}
        action={command.run}
      />
    );
  };
  if (tab === "edit" && state.mode === "edit") {
    const format = editor.currentState.formatting;
    const unavailable = disabled || !!format.readOnlyReason;
    return (
      <>
        <Group label={t.font}>
          <EditorFontControls
            commands={controller.commands}
            locale={state.locale}
            profile={controller.options.resources.profile}
            family={format.family}
            size={format.size}
            minSize={1}
            maxSize={409}
            sizeStep="any"
            disabled={unavailable}
            apply={(change, target) =>
              controller.run(() =>
                editor.formatCells(change, () =>
                  controller.commands.assertTarget(target),
                ),
              )
            }
          />
          <div className="od-xlsx-font-toggles">
            {(["bold", "italic", "underline", "strike"] as const).map((id) => (
              <EditorCommandButton key={id} id={id} iconOnly />
            ))}
          </div>
        </Group>
        <Group label={t.cellFormat}>
          <XlsxNumberFormat {...props} />
          <XlsxBorders {...props} />
          {(["left", "center", "right", "justify"] as const).map(
            (horizontal, index) => {
              const label = [
                t.alignLeft,
                t.alignCenter,
                t.alignRight,
                t.alignJustify,
              ][index]!;
              return (
                <button
                  key={horizontal}
                  type="button"
                  className="od-icon-command"
                  aria-label={label}
                  title={label}
                  aria-pressed={
                    format.horizontal === null
                      ? "mixed"
                      : format.horizontal === horizontal
                  }
                  disabled={unavailable}
                  onClick={() =>
                    controller.run(() => editor.formatCells({ horizontal }))
                  }
                >
                  <Icon name={`align-${horizontal}`} />
                </button>
              );
            },
          )}
        </Group>
        <Group label={t.clearMenu}>
          <RibbonMenu
            label={t.clearMenu}
            portal={workspace.portal}
            className="od-command"
            disabled={disabled}
            actions={[
              {
                label: t.clear,
                icon: "eraser",
                disabled,
                run: () => controller.run(() => editor.clear()),
              },
              {
                label: t.clearFormats,
                icon: "remove-format",
                disabled,
                run: () => controller.run(() => editor.clear("formats")),
              },
              {
                label: t.clearAll,
                icon: "trash",
                disabled,
                run: () => controller.run(() => editor.clear("all")),
              },
            ]}
          >
            <Icon name="eraser" />
            <span>{t.clearMenu}</span>
            <Icon name="chevron-down" />
          </RibbonMenu>
        </Group>
        <RibbonActions
          portal={workspace.portal}
          label={t.documentTools}
          more={t.moreActions}
          actions={[
            action(props, "format"),
            action(props, "dimensions"),
            action(props, "find"),
          ]}
        />
      </>
    );
  }
  if (tab === "view")
    return (
      <>
        <XlsxPrintCommands
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
        <Group label={t.documentTools}>
          {show("view")}
          {show("print")}
          {show("find")}
        </Group>
      </>
    );
  const group: { label: string; tasks: readonly Task[] } =
    tab === "insert"
      ? { label: t.insertTabLabel, tasks: ["objects", "tables"] }
      : tab === "data"
        ? {
            label: t.dataTab,
            tasks: [
              "sort",
              "filter",
              "validation",
              "pivots",
              "names",
              "outline",
            ],
          }
        : tab === "review"
          ? { label: t.reviewTab, tasks: ["review", "find"] }
          : { label: t.documentTools, tasks: ["find"] };
  return <Group label={group.label}>{group.tasks.map(show)}</Group>;
}

export function Properties(props: PanelProps) {
  const { controller, state, file, workspace } = props;
  const task = workspace?.task;
  if (!task || !Object.hasOwn(labels, task)) return null;
  const selected = task as Task;
  const t = messages(state.locale);
  const { editor } = file;
  const { sheet, selection, printSetup, printRange, headerFooter, names } =
    editor.currentState;
  const disabled = props.disabled || !!state.document?.stopped;
  const panel = { controller, state, editor, disabled };
  const views = {
    format: <XlsxFormat {...panel} />,
    objects: <XlsxFormat {...panel} section="objects" />,
    review: <XlsxFormat {...panel} section="review" />,
    find: <XlsxSearch {...panel} />,
    sheets: <XlsxSheets {...panel} task="sheets" />,
    dimensions: <XlsxSheets {...panel} task="dimensions" />,
    tables: <XlsxTablesPanel key={sheet} {...props} disabled={disabled} />,
    sort: <XlsxSort key={`${sheet}:${selection.address}`} {...panel} />,
    filter: <XlsxFilter key={sheet} {...panel} />,
    outline: <XlsxOutlinePanel {...props} disabled={disabled} />,
    pivots: <XlsxPivotsPanel key={sheet} {...props} editor={editor} />,
    names: <XlsxNames key={JSON.stringify(names)} {...panel} />,
    validation: (
      <>
        <XlsxFormat {...panel} section="validation" />
        <XlsxDataTools {...panel} />
      </>
    ),
    print: (
      <XlsxPrintSetup
        key={JSON.stringify([sheet, printSetup, printRange, headerFooter])}
        {...panel}
      />
    ),
    view: (
      <>
        <XlsxView {...panel} />
        <XlsxFrozen {...panel} disabled={disabled || state.mode === "view"} />
      </>
    ),
  } satisfies Record<Task, React.ReactNode>;
  if (state.mode === "view" && selected !== "find" && selected !== "view")
    return null;
  return (
    <EditorPanel
      key={selected}
      label={t[labels[selected]]}
      icon={icons[selected]}
      closeLabel={t.closePanel}
      close={() => {
        workspace?.showTask(undefined);
        editor.focus();
      }}
    >
      {views[selected]}
    </EditorPanel>
  );
}

export function Sheets({
  controller,
  state,
  file,
  disabled,
  workspace,
}: PanelProps) {
  return (
    <XlsxSheetStrip
      key={state.document?.documentId}
      controller={controller}
      state={state}
      editor={file.editor}
      disabled={disabled}
      manage={
        state.mode === "edit" ? () => workspace?.showTask("sheets") : undefined
      }
    />
  );
}
