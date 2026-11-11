import { useEffect, useState } from "react";
import { Command, Group } from "@open-document/ui/controls";
import type { IconName } from "@open-document/ui/icons";
import { messages, type MessageKey } from "@open-document/ui/messages";
import { EditorPanel } from "@open-document/ui";
import type { RibbonAction } from "@open-document/ui/ribbon";
import type { RibbonTab } from "@open-document/ui/types";
import type { PdfMetadata } from "../core/pdf.js";
import type { PanelProps } from "./context.js";
import { ObjectCommands } from "./objects.js";
import { PageTools } from "./pdf-pages.js";
import { PdfProperties, type PdfPropertyTask } from "./pdf-properties.js";
import { PdfSearch } from "./pdf-search.js";
import { AnnotationActions, FormActions, ReadingTools } from "./pdf-tools.js";
import { RedactionPanel } from "./redaction.js";

export const pdfTabs = [
  { id: "edit", label: "read", readOnly: true },
  { id: "insert", label: "edit" },
  { id: "annotations", label: "annotations" },
  { id: "view", label: "view", readOnly: true },
] as const satisfies readonly RibbonTab[];

const labels = {
  search: "search",
  content: "pdfContent",
  annotations: "annotations",
  pages: "pdfManagePages",
  forms: "pdfForms",
  metadata: "pdfFileProperties",
  redaction: "pdfRedaction",
  reading: "pdfReadingTools",
} as const satisfies Record<string, MessageKey>;

type Task = keyof typeof labels;
const icons = {
  search: "search",
  content: "inspector-panel",
  annotations: "comment-count",
  pages: "file-stack",
  forms: "text-input",
  metadata: "inspector-panel",
  redaction: "confidential-document",
  reading: "book",
} as const satisfies Record<Task, IconName>;

function propertyTask(property: string): PdfPropertyTask | undefined {
  switch (property.split(":", 1)[0]) {
    case "object":
    case "newText":
    case "imageCrop":
      return "content";
    case "annotation":
    case "annotationStyle":
    case "annotationReply":
    case "note":
    case "newDrawing":
    case "newInk":
      return "annotations";
    case "field":
    case "newField":
    case "fieldDesign":
    case "fieldName":
    case "fieldCopy":
      return "forms";
    case "metadata":
      return "metadata";
    case "pageGeometry":
      return "pages";
    default:
      return undefined;
  }
}

function taskAction(props: PanelProps, task: Task): RibbonAction {
  const { file, state, workspace } = props;
  const editor = file.editor;
  const snapshot = editor.getSnapshot();
  const selected = propertyTask(snapshot.data.property);
  return {
    label: messages(state.locale)[labels[task]],
    icon: icons[task],
    disabled:
      state.loading ||
      snapshot.paused ||
      snapshot.closed ||
      snapshot.composition ||
      !!snapshot.dragging ||
      !!snapshot.busy ||
      snapshot.data.applying ||
      (snapshot.draft && selected !== task),
    pressed: workspace?.task === task,
    run: () => {
      if (selected && selected !== task) editor.cancelDraft();
      workspace?.showTask(task);
    },
  };
}

export function pdfFileActions(props: PanelProps): readonly RibbonAction[] {
  return [taskAction(props, "metadata")];
}

export function pdfContextActions(props: PanelProps): readonly RibbonAction[] {
  return [taskAction(props, "search")];
}

export function FormatCommands(props: PanelProps & { tab: string }) {
  const t = messages(props.state.locale);
  const show = (task: Task) => {
    const action = taskAction(props, task);
    return (
      <Command
        label={action.label}
        icon={action.icon}
        disabled={!!action.disabled}
        pressed={action.pressed}
        action={action.run}
      />
    );
  };

  switch (props.tab) {
    case "edit":
      return (
        <Group label={t.read}>
          {show("search")}
          {show("reading")}
        </Group>
      );
    case "insert":
      return (
        <>
          <Group label={t.pdfContent}>{show("content")}</Group>
          <Group label={t.pages}>{show("pages")}</Group>
          <Group label={t.pdfForms}>{show("forms")}</Group>
        </>
      );
    case "annotations":
      return (
        <Group label={t.annotations}>
          {show("annotations")}
          {show("redaction")}
        </Group>
      );
    default:
      return null;
  }
}

export function Properties(props: PanelProps) {
  const { controller, state, file, disabled, workspace } = props;
  const editor = file.editor;
  const { property, applying, query } = editor.getSnapshot().data;
  const selected = propertyTask(property);
  const task = selected ?? workspace?.task;
  if (!task || !Object.hasOwn(labels, task)) return null;
  const id = task as Task;
  if (
    state.mode === "view" &&
    id !== "metadata" &&
    id !== "search" &&
    id !== "reading"
  )
    return null;
  const t = messages(state.locale);
  const editable = {
    ...props,
    disabled: disabled || !!query.readOnlyReason || !!state.document?.stopped,
  };
  const closeDisabled =
    applying ||
    !!state.document?.draft ||
    !!state.document?.dragging ||
    !!state.document?.composition;
  const close = () => {
    if (closeDisabled) return;
    controller.run(() => {
      if (property) editor.cancelDraft();
      workspace?.showTask();
      editor.focus();
    });
  };
  const native = (task: PdfPropertyTask) => (
    <PdfProperties
      {...props}
      task={task}
      disabled={disabled || !!state.document?.stopped}
    />
  );

  return (
    <EditorPanel
      label={t[labels[id]]}
      icon={icons[id]}
      closeLabel={t.closePanel}
      close={close}
      closeDisabled={closeDisabled}
    >
      <div className="od-pdf-task-content">
        {id === "search" && <PdfSearch {...props} />}
        {id === "reading" && <ReadingTools {...props} />}
        {id === "redaction" && <RedactionPanel {...editable} />}
        {id === "metadata" && (
          <>
            <FileDetails {...props} />
            {state.mode === "edit" && native("metadata")}
          </>
        )}
        {id === "content" && (
          <>
            {native("content")}
            {!property && <ObjectCommands {...editable} />}
          </>
        )}
        {id === "annotations" && (
          <>
            {native("annotations")}
            <AnnotationActions {...editable} />
          </>
        )}
        {id === "forms" && (
          <>
            {native("forms")}
            {!property && <FormActions {...editable} />}
          </>
        )}
        {id === "pages" && (
          <>
            <PageTools {...editable} />
            {native("pages")}
          </>
        )}
      </div>
    </EditorPanel>
  );
}

function FileDetails({ file, state }: PanelProps) {
  const [metadata, setMetadata] = useState<PdfMetadata>();
  const [error, setError] = useState("");
  const revision = state.document?.revision;
  useEffect(() => {
    let active = true;
    void file.editor.metadata().then(
      (result) => {
        if (active) {
          setMetadata(result);
          setError("");
        }
      },
      (failure: unknown) => {
        if (active)
          setError(
            failure instanceof Error ? failure.message : String(failure),
          );
      },
    );
    return () => {
      active = false;
    };
  }, [file, revision]);

  const zh = state.locale === "zh-CN";
  const labels = zh
    ? ["标题", "作者", "主题", "关键词"]
    : ["Title", "Author", "Subject", "Keywords"];
  return (
    <>
      {error && <p role="status">{error}</p>}
      {metadata?.readOnlyReason && (
        <p role="status">{metadata.readOnlyReason}</p>
      )}
      <dl className="od-pdf-file-details">
        {(["Title", "Author", "Subject", "Keywords"] as const).map(
          (key, index) => (
            <div key={key}>
              <dt>{labels[index]}</dt>
              <dd>{metadata?.fields[key] || "—"}</dd>
            </div>
          ),
        )}
      </dl>
    </>
  );
}
