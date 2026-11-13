export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import {
  EditorCommandButton,
  EditorFontControls,
  EditorPanel,
} from "@open-document/ui";
import { Command, Group, NativeSlot } from "@open-document/ui/controls";
import { Icon, type IconName } from "@open-document/ui/icons";
import { RibbonActions, type RibbonAction } from "@open-document/ui/ribbon";
import { messages, type MessageKey } from "@open-document/ui/messages";
import type { RibbonTab } from "@open-document/ui/types";
import { pptxSlideCountLimit } from "@open-document/wasm/engine-source";
import { PptxDesign } from "./pptx-design.js";
import { PptxGuides, PptxSnapping } from "./pptx-guides.js";
import { PptxObjects } from "./pptx-objects.js";
import { PptxArrange, PptxTransform } from "./pptx-arrange.js";
import { PptxAlignment } from "./pptx-alignment.js";
import { PptxSearch } from "./pptx-search.js";
import { PptxTheme, PptxThemeFonts } from "./pptx-theme.js";
import { PptxBackground, PptxSize, PptxSlideLayout } from "./pptx-page.js";
import { PptxFooter } from "./pptx-footer.js";
import { PptxSections } from "./pptx-sections.js";
import { PptxComments } from "./pptx-comments.js";
import { PptxViewSelector } from "./pptx-slides.js";
import { PptxImport } from "./pptx-import.js";
import { PptxShow } from "./pptx-show.js";
import { PptxTransitionForm } from "./pptx-transition.js";
import { PptxAnimations } from "./pptx-animations.js";
import { slideActions } from "./pptx-slide-actions.js";
import { pptxTextToggles } from "./pptx-format.js";

const tabs = [
  { id: "edit", label: "homeTab" },
  { id: "insert", label: "insertTabLabel" },
  { id: "design", label: "designTab" },
  { id: "animations", label: "animationTab" },
  { id: "review", label: "reviewTab" },
  { id: "view", label: "view", readOnly: true },
] as const satisfies readonly RibbonTab[];

export function pptxTabs(props?: PanelProps): readonly RibbonTab[] {
  const query = props?.file.editor.getSnapshot().data;
  const selected = query?.objects.find(
    (object) => object.id === query.selection.object,
  );
  if (!selected) return tabs;
  return [
    ...tabs,
    {
      id: "object",
      label: selected.kind === "image" ? "pictureTab" : "objectTools",
      contextual: true,
    },
  ];
}

const labels = {
  insert: "insertObject",
  import: "importSlidesTask",
  objects: "objects",
  arrange: "arrangeObjects",
  find: "findReplace",
  layout: "slideLayout",
  background: "slideBackground",
  design: "designTab",
  sections: "sections",
  transitions: "transitionTab",
  animations: "animationTab",
  show: "presentationSettings",
  view: "pptxEditView",
  review: "reviewTab",
} as const satisfies Record<string, MessageKey>;

type Task = keyof typeof labels;
const icons = {
  insert: "shapes",
  import: "upload",
  objects: "inspector-panel",
  arrange: "align-objects-left",
  find: "search",
  layout: "presentation",
  background: "background-color",
  design: "palette",
  sections: "list-nested",
  transitions: "ease-out",
  animations: "sparkles",
  show: "play",
  view: "file-preview",
  review: "comment-count",
} as const satisfies Record<Task, IconName>;

function taskAction(props: PanelProps, task: Task): RibbonAction {
  const { state, workspace } = props;
  return {
    label: messages(state.locale)[labels[task]],
    icon: icons[task],
    disabled: state.loading,
    pressed: workspace?.task === task,
    run: () => workspace?.showTask(task),
  };
}

export function pptxContextActions(props: PanelProps): readonly RibbonAction[] {
  const find = taskAction(props, "find");
  if (props.state.mode === "view") return [find];
  if (props.file.editor.getSnapshot().data.selection.object)
    return [taskAction(props, "objects"), taskAction(props, "arrange"), find];
  return [taskAction(props, "layout"), find];
}

export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab, workspace } = props;
  const t = messages(state.locale);
  const { editor } = file;
  const query = editor.getSnapshot().data;
  if (!workspace) return null;
  const show = (id: Task) => {
    const action = taskAction(props, id);
    return (
      <Command
        key={id}
        label={action.label}
        icon={action.icon}
        action={action.run}
        disabled={!!action.disabled}
        pressed={action.pressed}
      />
    );
  };
  const normal = query.editView.kind === "slide";
  switch (tab) {
    case "edit":
      if (state.mode === "view")
        return <Group label={t.documentTools}>{show("find")}</Group>;
      if (!normal)
        return (
          <Group label={t.documentTools}>
            {show("view")}
            {show("design")}
            {show("background")}
            {show("objects")}
          </Group>
        );
      return (
        <>
          <Group label={t.manageSlides}>
            <Command
              label={t.addSlide}
              icon="file-plus"
              disabled={
                disabled ||
                query.slides.length >= pptxSlideCountLimit ||
                !!query.slideOrderReason
              }
              action={() =>
                controller.run(() => editor.editSlides({ action: "add" }))
              }
            />
            {show("layout")}
            {show("sections")}
          </Group>
          <Group label={t.documentTools}>
            {show("objects")}
            {show("find")}
          </Group>
          <RibbonActions
            portal={workspace.portal}
            label={t.slideActions}
            more={t.moreActions}
            actions={slideActions(
              props,
              query.slides.findIndex((slide) => slide.id === query.slide),
            )}
          />
        </>
      );
    case "insert":
      return (
        <Group label={t.insertTabLabel}>
          {show("insert")}
          {normal && show("import")}
        </Group>
      );
    case "design":
      return (
        <Group label={t.designTab}>
          {normal && show("layout")}
          {show("background")}
          {show("design")}
        </Group>
      );
    case "animations":
      return (
        normal && (
          <Group label={t.animationTab}>
            {show("transitions")}
            {show("animations")}
          </Group>
        )
      );
    case "review":
      return (
        <Group label={t.reviewTab}>
          {normal && show("review")}
          {show("find")}
        </Group>
      );
    case "view":
      return (
        <Group label={t.view}>
          {show("view")}
          {normal && show("show")}
          {show("find")}
        </Group>
      );
    case "object":
      return (
        <>
          {!query.formatting.reason && (
            <Group label={t.textFormat}>
              <EditorFontControls
                commands={controller.commands}
                locale={state.locale}
                profile={controller.options.resources.profile}
                family={query.formatting.font}
                size={query.formatting.size}
                minSize={1}
                maxSize={1024}
                sizeStep={0.01}
                disabled={disabled || state.saving}
                apply={(change, target) =>
                  controller.run(() =>
                    editor.editObjects(
                      {
                        action: "textFormat",
                        format:
                          "family" in change ? { font: change.family } : change,
                      },
                      () => controller.commands.assertTarget(target),
                    ),
                  )
                }
              />
              {pptxTextToggles.map((id) => (
                <EditorCommandButton key={id} id={id} iconOnly />
              ))}
            </Group>
          )}
          <Group label={t.objectTools}>
            {show("objects")}
            {show("arrange")}
            <Command
              label={t.groupObjects}
              disabled={disabled || !!query.groupReason}
              action={() =>
                controller.run(() => editor.editObjects({ action: "group" }))
              }
            >
              <Icon name="group" />
            </Command>
            <Command
              label={t.ungroupObjects}
              disabled={disabled || !!query.ungroupReason}
              action={() =>
                controller.run(() => editor.editObjects({ action: "ungroup" }))
              }
            >
              <Icon name="ungroup" />
            </Command>
          </Group>
        </>
      );
    default:
      return null;
  }
}

export function Properties(props: PanelProps) {
  const { controller, state, file, disabled, workspace } = props;
  const task = workspace?.task;
  if (!task || !Object.hasOwn(labels, task)) return null;
  if (
    state.mode === "view" &&
    task !== "find" &&
    task !== "show" &&
    task !== "view"
  )
    return null;
  const t = messages(state.locale);
  const { editor } = file;
  const query = editor.getSnapshot().data;
  const snapshot = editor.getSnapshot();
  const readDisabled =
    state.loading ||
    snapshot.paused ||
    snapshot.stopped ||
    snapshot.closed ||
    snapshot.composition ||
    snapshot.dragging ||
    !!snapshot.busy;
  const form = { controller, state, editor, disabled };
  const base = { controller, state, file, disabled };
  const normal = query.editView.kind === "slide";
  const selected = query.objects.find(
    (object) => object.id === query.selection.object,
  );
  const views = {
    insert: <PptxObjects {...form} task="insert" />,
    import: <PptxImport {...form} />,
    objects: (
      <>
        <NativeSlot node={editor.objectList} />
        {selected && (
          <>
            <div className="flex gap-1" role="group" aria-label={t.edit}>
              <button
                type="button"
                disabled={disabled}
                aria-pressed={query.selection.mode === "object"}
                onClick={() =>
                  controller.run(() =>
                    editor.selectObjects(
                      query.selection.objects,
                      query.selection.object,
                    ),
                  )
                }
              >
                <Icon name="selection" />
                {t.objectMode}
              </button>
              <button
                type="button"
                disabled={disabled || !!selected.textReadOnlyReason}
                aria-pressed={query.selection.mode === "text"}
                onClick={() =>
                  controller.run(() =>
                    editor.select(query.selection.object, "text"),
                  )
                }
              >
                <Icon name="text" />
                {t.textMode}
              </button>
            </div>
            {(selected.readOnlyReason || selected.textReadOnlyReason) && (
              <p>{selected.readOnlyReason || selected.textReadOnlyReason}</p>
            )}
            <PptxObjects {...form} task="object" />
          </>
        )}
      </>
    ),
    arrange: (
      <>
        <PptxAlignment {...form} />
        <PptxArrange
          key={JSON.stringify([query.selection, query.revision])}
          {...form}
        />
        <PptxTransform {...form} />
      </>
    ),
    find: <PptxSearch {...form} disabled={readDisabled} />,
    layout: normal && (
      <PptxSlideLayout
        key={query.slide + ":" + query.slideLayout.current}
        {...base}
      />
    ),
    background: (
      <PptxBackground
        key={JSON.stringify([query.slide, query.background])}
        {...base}
      />
    ),
    design: normal ? (
      <>
        <PptxTheme {...base} />
        <PptxThemeFonts {...base} />
        <PptxSize key={query.revision} {...base} />
        <PptxFooter
          key={JSON.stringify([query.slide, query.footer])}
          {...base}
        />
      </>
    ) : (
      <PptxDesign key={query.slide} {...base} />
    ),
    sections: normal && (
      <PptxSections key={`${query.slide}:${query.revision}`} {...form} />
    ),
    transitions: normal && (
      <PptxTransitionForm key={`${query.slide}:${query.revision}`} {...form} />
    ),
    animations: normal && (
      <PptxAnimations key={`${query.slide}:${query.revision}`} {...form} />
    ),
    review: normal && <PptxComments key={query.slide} {...base} />,
    show: normal && <PptxShow {...form} disabled={readDisabled} />,
    view: (
      <>
        <PptxViewSelector {...props} disabled={readDisabled} />
        {state.mode === "edit" && (
          <>
            <PptxGuides key={JSON.stringify(query.guides)} {...base} />
            <PptxSnapping key={JSON.stringify(query.snapping)} {...base} />
          </>
        )}
      </>
    ),
  } satisfies Record<Task, React.ReactNode>;
  const selectedTask = task as Task;
  const content = views[selectedTask];
  if (!content) return null;
  return (
    <EditorPanel
      key={selectedTask}
      label={t[labels[selectedTask]]}
      icon={icons[selectedTask]}
      closeLabel={t.closePanel}
      close={() => {
        workspace?.showTask(undefined);
        editor.focus();
      }}
    >
      {content}
    </EditorPanel>
  );
}
