import { useState, useSyncExternalStore, type ReactNode } from "react";
import { CSPProvider } from "@base-ui/react/csp-provider";
import type { EditorController } from "./controller.js";
import { EditorSettings, LeaveConfirmation } from "./controls.js";
import { EditorRibbon, EditorSurface } from "./ribbon.js";
import { Details, Zoom } from "./panels.js";
import { Icon } from "./icons.js";
import { AccentIcon, type AccentIconName } from "./accent-icons.js";
import { messages } from "./messages.js";
import type { EditorHost, EditorSlots, EditorSlotContext } from "./types.js";
import {
  EditorCommandButton,
  EditorCommandProvider,
  useEditorCommand,
} from "./commands.js";

const badges: Record<string, AccentIconName> = {
  docx: "file-text",
  xlsx: "file-spreadsheet",
  pptx: "presentation",
  pdf: "file",
};

export function EditorShell<E extends EditorHost>({
  controller,
  portal,
}: {
  controller: EditorController<E>;
  portal: HTMLElement;
}) {
  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getUiSnapshot,
    controller.getUiSnapshot,
  );
  const [notice, setNotice] = useState<string>();
  const [task, setTask] = useState<{
    documentId: string | undefined;
    id: string;
  }>();
  const t = messages(state.locale),
    file = state.file,
    snapshot = state.document;
  const save = useEditorCommand("save", controller.commands);
  const disabled =
    state.loading ||
    !!snapshot?.paused ||
    !!snapshot?.composition ||
    !!snapshot?.dragging ||
    !!snapshot?.closed ||
    !!snapshot?.busy;
  const editDisabled =
    disabled ||
    state.mode === "view" ||
    !!snapshot?.stopped ||
    !!snapshot?.readOnlyReason;
  const panel = file
    ? {
        controller,
        state,
        file,
        disabled,
        workspace: {
          task:
            task?.documentId === snapshot?.documentId ? task?.id : undefined,
          portal,
          showTask: (id?: string) =>
            setTask(id ? { id, documentId: snapshot?.documentId } : undefined),
        },
      }
    : undefined;
  const context: EditorSlotContext | undefined = file &&
    snapshot && {
      commands: controller.commands,
      snapshot,
      mode: state.mode,
      portal,
      focus: () => file.editor.focus(),
    };
  const slot = (name: keyof EditorSlots, fallback: ReactNode) => {
    const custom = controller.options.slots?.[name];
    if (custom === undefined) return fallback;
    if (!context || !custom) return null;
    const content = custom(context);
    return name === "toolbar" ? (
      <div className="od-custom-toolbar" role="group" aria-label={t.edit}>
        {content}
      </div>
    ) : (
      content
    );
  };
  const saveState =
    state.loading || state.saving
      ? "busy"
      : snapshot?.modified
        ? "modified"
        : "saved";
  const recover = () => controller.run(() => file?.recover());
  return (
    <EditorCommandProvider commands={controller.commands}>
      <CSPProvider nonce={controller.options.styleNonce}>
        <section
          className="od-root"
          lang={state.locale}
          aria-label={`${controller.product.format.toUpperCase()} editor`}
          onKeyDown={(event) => {
            if (
              event.defaultPrevented ||
              event.nativeEvent.isComposing ||
              snapshot?.composition
            )
              return;
            if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
            const target = event.nativeEvent.composedPath()[0];
            if (!(target instanceof HTMLElement)) return;
            const root = target.getRootNode();
            if (
              !(root instanceof ShadowRoot) ||
              root !== controller.host.shadowRoot ||
              root.activeElement !== target
            )
              return;
            const key = event.key.toLowerCase();
            if (key === "s") {
              event.preventDefault();
              if (!target.closest('[role="dialog"]'))
                void controller.commands.execute("save").catch(() => {});
              return;
            }
            const formatCommand =
              key === "b"
                ? "bold"
                : key === "i"
                  ? "italic"
                  : key === "u"
                    ? "underline"
                    : undefined;
            if (
              formatCommand &&
              controller.commands.getSnapshot(formatCommand) &&
              !target.closest('[role="dialog"]') &&
              !target.matches("input,select,[contenteditable=true]") &&
              (!target.matches("textarea") || !!target.closest(".od-surface"))
            ) {
              event.preventDefault();
              if (controller.commands.getSnapshot(formatCommand)?.enabled)
                void controller.commands.execute(formatCommand).catch(() => {});
              return;
            }
            if (
              !file ||
              disabled ||
              target.closest('[role="dialog"]') ||
              target.matches("input,textarea,select,[contenteditable=true]") ||
              (key !== "z" && key !== "y")
            )
              return;
            event.preventDefault();
            const id = key === "y" || event.shiftKey ? "redo" : "undo";
            if (controller.commands.getSnapshot(id)?.enabled)
              void controller.commands
                .execute(id)
                .then(() => {
                  if (
                    controller.getUiSnapshot().file === file &&
                    !file.editor.getSnapshot().closed
                  )
                    file.editor.focus();
                })
                .catch(() => {});
          }}
        >
          <header className="od-caption">
            <div className="od-caption-main">
              <span
                className="od-doc-badge"
                data-format={controller.product.format}
                aria-hidden="true"
              >
                <AccentIcon
                  name={badges[controller.product.format] ?? "file"}
                />
              </span>
              <span className="od-title" title={state.name}>
                {state.name}
              </span>
              <span
                className="od-save-state"
                data-state={saveState}
                role="status"
              >
                {state.loading
                  ? t.loading
                  : state.saving
                    ? t.saving
                    : snapshot?.modified
                      ? t.modified
                      : t.saved}
              </span>
            </div>
            <div className="od-caption-actions">
              {controller.product.tabs &&
                state.mode === "edit" &&
                controller.options.slots?.toolbar === undefined && (
                  <div
                    className="od-quick-history"
                    role="group"
                    aria-label={t.history}
                  >
                    <EditorCommandButton id="undo" />
                    <EditorCommandButton id="redo" />
                  </div>
                )}
              {slot(
                "actions",
                panel && controller.product.render("actions", panel),
              )}
              <button
                type="button"
                className="od-caption-command"
                data-emphasis={
                  (snapshot?.modified && save?.enabled) || undefined
                }
                disabled={!save?.enabled}
                aria-description={save?.disabledReason}
                onClick={() =>
                  void controller.commands.execute("save").catch(() => {})
                }
              >
                <Icon name="save" />
                {save?.label ?? t.save}
              </button>
              <EditorSettings
                controller={controller}
                state={state}
                portal={portal}
              />
            </div>
          </header>
          {slot(
            "toolbar",
            <EditorRibbon
              controller={controller}
              state={state}
              panel={panel}
              portal={portal}
              editDisabled={editDisabled}
            />,
          )}
          {(state.error ||
            snapshot?.error ||
            snapshot?.stopped ||
            state.message) && (
            <div
              className="od-message"
              data-error={
                !!(state.error || snapshot?.error || snapshot?.stopped)
              }
            >
              <span role={state.error || snapshot?.error ? "alert" : "status"}>
                {state.error ||
                  snapshot?.error ||
                  (snapshot?.stopped ? t.stopped : state.message)}
              </span>
              {snapshot?.stopped && (
                <button type="button" disabled={disabled} onClick={recover}>
                  {t.recover}
                </button>
              )}
            </div>
          )}
          {file &&
            Object.keys(controller.options.resources.profile).some(
              (key) => key === "*" || key.startsWith("*|"),
            ) &&
            notice !== snapshot?.documentId && (
              <div className="od-notice">
                <AccentIcon name="triangle-alert" />
                <span role="status">{t.fontFallbackWarning}</span>
                <button
                  type="button"
                  className="od-icon-command"
                  aria-label={t.dismiss}
                  title={t.dismiss}
                  onClick={() => setNotice(snapshot?.documentId)}
                >
                  <Icon name="close" />
                </button>
              </div>
            )}
          <div className="od-workbench">
            {slot(
              "navigation",
              panel && controller.product.render("pages-list", panel),
            )}
            <div className="od-workspace">
              {panel &&
                controller.product.render("before-surface", {
                  ...panel,
                  disabled: editDisabled,
                })}
              <EditorSurface
                controller={controller}
                panel={panel}
                portal={portal}
              />
              {panel &&
                controller.product.render("below-surface", {
                  ...panel,
                  disabled: editDisabled,
                })}
              {state.loading && (
                <div className="od-loading" role="status">
                  <div>
                    <p>{t.loading}</p>
                    <button
                      type="button"
                      onClick={() => controller.cancelOpening()}
                    >
                      {t.cancel}
                    </button>
                  </div>
                </div>
              )}
            </div>
            {slot(
              "properties",
              panel &&
                controller.product.render("properties", {
                  ...panel,
                  disabled: disabled || state.mode === "view",
                }),
            )}
          </div>
          {panel && controller.product.render("after-surface", panel)}
          <footer className="od-status" aria-label={t.ready}>
            {slot(
              "status",
              panel && controller.product.render("status", panel),
            )}
            {snapshot?.draft && <span>{t.draftTitle}</span>}
            <span>
              {controller.product.addressStatus
                ? `${t.address} ${snapshot?.selection ?? ""}`
                : `${(snapshot?.page ?? 0) + 1} / ${snapshot?.pageCount ?? 0}`}
            </span>
            <span className="od-status-spacer" />
            {panel && <Zoom {...panel} />}
            <Details state={state} />
          </footer>
          <LeaveConfirmation
            controller={controller}
            state={state}
            portal={portal}
          />
        </section>
      </CSPProvider>
    </EditorCommandProvider>
  );
}
