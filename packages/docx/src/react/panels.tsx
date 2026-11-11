export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import { Command, Group } from "@open-document/ui/controls";
import type { IconName } from "@open-document/ui/icons";
import { messages, type MessageKey } from "@open-document/ui/messages";
import { EditorTablePicker } from "@open-document/ui";
import { RibbonActions, type RibbonAction } from "@open-document/ui/ribbon";
import type { RibbonTab } from "@open-document/ui/types";
import { DocxFormatCommands } from "./docx-format.js";
import { DocxProperties } from "./docx-properties.js";

const tabs: readonly RibbonTab[] = [
  { id: "edit", label: "homeTab" },
  { id: "insert", label: "insertTabLabel" },
  { id: "layout", label: "layoutTab" },
  { id: "review", label: "reviewTab" },
  { id: "view", label: "view", readOnly: true },
];

export function docxTabs(props?: PanelProps): readonly RibbonTab[] {
  if (!props) return tabs;
  const { editor } = props.file;
  const snapshot = editor.getSnapshot();
  const { selection, formatting } = snapshot.data;
  const line = editor.layout.semantics[snapshot.page]?.lines.find(
    (item) => item.paragraph === selection?.focus.paragraph,
  );
  const contextual: RibbonTab[] = [];
  if (formatting?.table || formatting?.cellSelection.value)
    contextual.push({ id: "table", label: "tableTab", contextual: true });
  if (editor.pictureSelected)
    contextual.push({ id: "picture", label: "pictureTab", contextual: true });
  if (line?.container === -1 || line?.container === -2)
    contextual.push({
      id: "header-footer",
      label: "headerFooterTab",
      contextual: true,
    });
  return [...tabs, ...contextual];
}

function taskAction(
  props: PanelProps,
  id: string,
  label: MessageKey,
  icon: IconName,
): RibbonAction {
  return {
    label: messages(props.state.locale)[label],
    icon,
    disabled: props.state.loading,
    pressed: props.workspace?.task === id,
    run: () => props.workspace?.showTask(id),
  };
}

export function docxContextActions(props: PanelProps): readonly RibbonAction[] {
  const actions = [taskAction(props, "find", "findReplace", "search")];
  if (props.state.mode === "view") return actions;
  if (props.file.editor.pictureSelected)
    actions.unshift(taskAction(props, "insert-picture", "pictureTab", "image"));
  else if (props.file.editor.getSnapshot().data.formatting?.table)
    actions.unshift(taskAction(props, "table", "tableTab", "table-cells"));
  else
    actions.unshift(
      taskAction(props, "paragraph", "paragraphOptions", "paragraph-spacing"),
    );
  return actions;
}

function TaskCommands({
  label,
  actions,
}: {
  label: string;
  actions: readonly RibbonAction[];
}) {
  return (
    <Group label={label}>
      {actions.map((action) => (
        <Command
          key={action.label}
          label={action.label}
          icon={action.icon}
          action={action.run}
          disabled={!!action.disabled}
          pressed={action.pressed}
        />
      ))}
    </Group>
  );
}

export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab, workspace } = props;
  const t = messages(state.locale);
  if (!workspace) return null;
  const action = (id: string, label: MessageKey, icon: IconName) =>
    taskAction(props, id, label, icon);
  const inputs = { controller, state, editor: file.editor, disabled };
  const find = action("find", "findReplace", "search");
  switch (tab) {
    case "edit":
      if (state.mode === "view")
        return <TaskCommands label={t.documentTools} actions={[find]} />;
      return (
        <>
          <DocxFormatCommands {...inputs} portal={workspace.portal} />
          <RibbonActions
            portal={workspace.portal}
            label={t.documentTools}
            more={t.moreActions}
            actions={[
              action("font", "fontOptions", "font-size"),
              action("paragraph", "paragraphOptions", "paragraph-spacing"),
              action("styles", "stylesPanel", "format-painter"),
              find,
            ]}
          />
        </>
      );
    case "insert": {
      const snapshot = file.editor.getSnapshot();
      const data = snapshot.data;
      const paragraph = data.selection?.focus.paragraph;
      const linkAction = action("link", "textHyperlink", "link-plus");
      const body = file.editor.layout.semantics[snapshot.page]?.lines.some(
        (line) => line.paragraph === paragraph && line.container === 0,
      );
      return (
        <>
          <Group label={t.insertTabLabel}>
            <EditorTablePicker
              commands={controller.commands}
              portal={workspace.portal}
              label={t.insertTable}
              gridLabel={t.tableGrid}
              describe={(rows, columns) =>
                t.sizeInRowsColumns
                  .replace("{rows}", String(rows))
                  .replace("{columns}", String(columns))
              }
              disabled={
                disabled ||
                !body ||
                !data.formatting ||
                !!data.formatting.reason
              }
              insert={(rows, columns, target) =>
                controller.run(() =>
                  file.editor.tables.insertTable(rows, columns, () =>
                    controller.commands.assertTarget(target),
                  ),
                )
              }
            />
            {[
              action("table", "tableTab", "table-cells"),
              action("insert-picture", "pictureTab", "image"),
              action("illustrations", "insertObjects", "shapes"),
              action("math", "mathExpressions", "function-fx"),
            ].map((entry) => (
              <Command
                key={entry.label}
                label={entry.label}
                icon={entry.icon}
                action={entry.run}
                disabled={!!entry.disabled}
                pressed={entry.pressed}
              />
            ))}
          </Group>
          <Group label={t.insertText}>
            <Command
              label={linkAction.label}
              icon={linkAction.icon}
              action={linkAction.run}
              disabled={!!linkAction.disabled}
              pressed={linkAction.pressed}
            />
            <DocxFormatCommands
              {...inputs}
              section="insert"
              portal={workspace.portal}
            />
          </Group>
          <TaskCommands
            label={t.referencesTab}
            actions={[
              action("references", "documentOverview", "table-of-contents"),
              action("notes", "noteNumbering", "list-ordered"),
            ]}
          />
        </>
      );
    }
    case "layout":
      return (
        <TaskCommands
          label={t.layoutTab}
          actions={[
            action("layout", "pageSetup", "page-margins"),
            action("running", "headerFooterTab", "layout-header"),
            action("design", "theme", "palette"),
          ]}
        />
      );
    case "references":
      return (
        <TaskCommands
          label={t.referencesTab}
          actions={[
            action("references", "documentOverview", "table-of-contents"),
            action("notes", "noteNumbering", "list-ordered"),
          ]}
        />
      );
    case "review":
      return (
        <TaskCommands
          label={t.reviewTab}
          actions={[action("review", "reviewTab", "comment-count"), find]}
        />
      );
    case "table":
      return (
        <TaskCommands
          label={t.tableTab}
          actions={[action("table", "tableTab", "table-cells")]}
        />
      );
    case "picture":
      return (
        <TaskCommands
          label={t.pictureTab}
          actions={[action("insert-picture", "pictureTab", "image")]}
        />
      );
    case "header-footer":
      return (
        <TaskCommands
          label={t.headerFooterTab}
          actions={[action("running", "headerFooterTab", "layout-header")]}
        />
      );
    case "view":
      return <TaskCommands label={t.documentTools} actions={[find]} />;
    default:
      return null;
  }
}

export function Properties({
  controller,
  state,
  file,
  disabled,
  workspace,
}: PanelProps) {
  const task = workspace?.task;
  if (!task || (state.mode === "view" && task !== "find")) return null;
  return (
    <DocxProperties
      key={file.editor.getSnapshot().documentId + ":" + task}
      controller={controller}
      state={state}
      editor={file.editor}
      disabled={disabled && state.mode !== "view"}
      task={task}
      close={() => {
        workspace.showTask(undefined);
        file.editor.focus();
      }}
    />
  );
}
