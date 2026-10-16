import { useState, useSyncExternalStore } from "react";
import { Tabs } from "@base-ui/react/tabs";
import { CSPProvider } from "@base-ui/react/csp-provider";
import type { EditorController } from "./controller.js";
import {
  ClipboardGroup,
  Command,
  FileMenu,
  Group,
  LeaveConfirmation,
  NativeSlot,
} from "./controls.js";
import {
  Details,
  FormatCommands,
  Navigation,
  PageList,
  Properties,
  Sheets,
  Zoom,
} from "./panels.js";
import { messages } from "./messages.js";
import { Icon } from "./icons.js";
import { XlsxFormula } from "./xlsx-formula.js";

export function EditorShell({
  controller,
  portal,
}: {
  controller: EditorController;
  portal: HTMLElement;
}) {
  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getUiSnapshot,
    controller.getUiSnapshot,
  );
  const [tab, setTab] = useState("edit"),
    [collapsed, setCollapsed] = useState(false);
  const t = messages(state.locale),
    file = state.file,
    snapshot = state.document;
  const disabled =
    state.loading ||
    !!snapshot?.paused ||
    !!snapshot?.composition ||
    !!snapshot?.dragging ||
    !!snapshot?.closed ||
    !!snapshot?.busy;
  const editDisabled =
    disabled || !!snapshot?.stopped || !!snapshot?.readOnlyReason;
  const panel = file ? { controller, state, file, disabled } : undefined;
  const recover = () =>
    controller.run(() =>
      file?.format === "docx" ? file.editor.resume() : file?.editor.refresh(),
    );
  return (
    <CSPProvider nonce={controller.options.styleNonce}>
      <section
        className="od-root"
        aria-label={`${controller.options.format.toUpperCase()} editor`}
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
              controller.run(controller.save);
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
          controller.run(async () => {
            if (key === "y" || event.shiftKey) await file.editor.redo();
            else await file.editor.undo();
            if (
              controller.getUiSnapshot().file === file &&
              !file.editor.getSnapshot().closed
            )
              file.editor.focus();
          });
        }}
      >
        <header className="od-caption">
          <span className="od-title" title={state.name}>
            {state.name}
          </span>
          <button
            type="button"
            disabled={
              !file ||
              state.loading ||
              state.saving ||
              !!snapshot?.composition ||
              !!snapshot?.dragging
            }
            onClick={() => controller.run(controller.save)}
          >
            {state.saving ? t.saving : t.save}
          </button>
          <label className="od-setting">
            <span>{t.theme}</span>
            <select
              aria-label={t.theme}
              value={state.theme}
              onChange={(event) =>
                controller.setTheme(
                  event.currentTarget.value === "dark" ? "dark" : "light",
                )
              }
            >
              <option value="light">{t.light}</option>
              <option value="dark">{t.dark}</option>
            </select>
          </label>
          <label className="od-setting">
            <span>{t.language}</span>
            <select
              aria-label={t.language}
              value={state.locale}
              onChange={(event) =>
                controller.setLocale(
                  event.currentTarget.value === "zh-CN" ? "zh-CN" : "en-US",
                )
              }
            >
              <option value="en-US">English</option>
              <option value="zh-CN">中文</option>
            </select>
          </label>
        </header>
        <Tabs.Root
          value={tab}
          onValueChange={(value) => {
            if (typeof value === "string") setTab(value);
          }}
        >
          <div className="od-tabs">
            <FileMenu controller={controller} state={state} portal={portal} />
            <Tabs.List className="flex" aria-label={t.edit}>
              <Tabs.Tab value="edit">
                {file?.format === "pdf" ? t.read : t.edit}
              </Tabs.Tab>
              <Tabs.Tab value="view">{t.view}</Tabs.Tab>
              {controller.options.format === "pdf" && (
                <>
                  <Tabs.Tab value="pages">{t.pages}</Tabs.Tab>
                  <Tabs.Tab value="annotations">{t.annotations}</Tabs.Tab>
                </>
              )}
            </Tabs.List>
            <button
              type="button"
              className="od-collapse"
              aria-label={collapsed ? t.expand : t.collapse}
              aria-expanded={!collapsed}
              onClick={() => setCollapsed(!collapsed)}
            >
              {collapsed ? "⌄" : "⌃"}
            </button>
          </div>
          {!collapsed && file && panel && (
            <>
              <Tabs.Panel value="edit" className="od-ribbon">
                <ClipboardGroup
                  key={snapshot?.documentId}
                  controller={controller}
                  state={state}
                  file={file}
                  portal={portal}
                  disabled={disabled || !!snapshot?.stopped}
                />
                <Group label={t.history}>
                  <Command
                    label={t.undo}
                    disabled={disabled || !snapshot?.canUndo}
                    action={() => controller.run(() => file.editor.undo())}
                  >
                    <Icon name="undo" />
                  </Command>
                  <Command
                    label={t.redo}
                    disabled={disabled || !snapshot?.canRedo}
                    action={() => controller.run(() => file.editor.redo())}
                  >
                    <Icon name="redo" />
                  </Command>
                </Group>
                <FormatCommands
                  {...panel}
                  disabled={
                    file.format === "pptx"
                      ? disabled || !!snapshot?.stopped
                      : editDisabled
                  }
                  tab="edit"
                />
              </Tabs.Panel>
              <Tabs.Panel value="view" className="od-ribbon">
                {file.format !== "xlsx" && <Navigation {...panel} />}
                <Group label={t.zoom}>
                  <Zoom {...panel} />
                </Group>
                <FormatCommands {...panel} tab="view" />
                <Group label={t.refresh}>
                  <Command
                    label={snapshot?.stopped ? t.recover : t.refresh}
                    disabled={disabled}
                    action={recover}
                  />
                </Group>
              </Tabs.Panel>
              {file.format === "pdf" && (
                <>
                  <Tabs.Panel value="pages" className="od-ribbon">
                    <FormatCommands
                      {...panel}
                      disabled={editDisabled}
                      tab="pages"
                    />
                  </Tabs.Panel>
                  <Tabs.Panel value="annotations" className="od-ribbon">
                    <FormatCommands
                      {...panel}
                      disabled={editDisabled}
                      tab="annotations"
                    />
                  </Tabs.Panel>
                </>
              )}
            </>
          )}
        </Tabs.Root>
        {(state.error ||
          snapshot?.error ||
          snapshot?.stopped ||
          state.message) && (
          <div
            className="od-message"
            data-error={!!(state.error || snapshot?.error || snapshot?.stopped)}
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
        <div className="od-workbench">
          {panel && <PageList {...panel} />}
          <div className="od-workspace">
            {file?.format === "xlsx" && (
              <XlsxFormula
                key={snapshot?.documentId}
                controller={controller}
                state={state}
                editor={file.editor}
                disabled={disabled || !!snapshot?.stopped}
              />
            )}
            <NativeSlot node={controller.surfaces} className="od-surfaces" />
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
          {panel && <Properties key={snapshot?.documentId} {...panel} />}
        </div>
        {panel && <Sheets {...panel} />}
        <footer className="od-status" aria-label={t.ready}>
          <span role="status">
            {state.loading
              ? t.loading
              : state.saving
                ? t.saving
                : snapshot?.modified
                  ? t.modified
                  : t.saved}
          </span>
          {snapshot?.draft && <span>{t.draftTitle}</span>}
          <span>
            {file?.format === "xlsx"
              ? `${t.address} ${snapshot?.selection ?? ""}`
              : `${(snapshot?.page ?? 0) + 1} / ${snapshot?.pageCount ?? 0}`}
          </span>
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
  );
}
