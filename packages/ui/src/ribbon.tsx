import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { Tabs } from "@base-ui/react/tabs";
import { Menu } from "@base-ui/react/menu";
import { ContextMenu } from "@base-ui/react/context-menu";
import {
  ClipboardGroup,
  Command,
  FileMenu,
  Group,
  NativeSlot,
} from "./controls.js";
import { EditorCommandButton, type CommandTarget } from "./commands.js";
import { Icon, type IconName } from "./icons.js";
import { Navigation, Zoom } from "./panels.js";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import type { EditorHost, PanelProps, RibbonTab } from "./types.js";

export interface RibbonAction {
  readonly label: string;
  readonly icon: IconName;
  readonly disabled?: boolean;
  /** True while the action's task panel is open. */
  readonly pressed?: boolean;
  run(): void;
}

export function RibbonMenu({
  actions,
  label,
  group,
  portal,
  className,
  disabled,
  onOpenChange,
  children,
}: {
  actions: readonly RibbonAction[];
  label: string;
  group?: string;
  portal: HTMLElement;
  className: string;
  disabled?: boolean;
  onOpenChange?(open: boolean): void;
  children: ReactNode;
}) {
  return (
    <Menu.Root modal={false} onOpenChange={onOpenChange}>
      <Menu.Trigger
        className={className}
        aria-label={label}
        disabled={disabled ?? false}
      >
        {children}
      </Menu.Trigger>
      <Menu.Portal container={portal}>
        <Menu.Positioner
          className="od-menu-positioner"
          sideOffset={4}
          align="start"
        >
          <Menu.Popup className="od-menu">
            <Menu.Group>
              {group && (
                <Menu.GroupLabel className="od-menu-label">
                  {group}
                </Menu.GroupLabel>
              )}
              {actions.map((action) => (
                <Menu.Item
                  key={action.label}
                  disabled={!!action.disabled}
                  onClick={action.run}
                >
                  <Icon name={action.icon} />
                  {action.label}
                </Menu.Item>
              ))}
            </Menu.Group>
          </Menu.Popup>
        </Menu.Positioner>
      </Menu.Portal>
    </Menu.Root>
  );
}

/** Keep secondary actions reachable without making the tool strip scroll sideways. */
export function RibbonActions({
  actions,
  label,
  more,
  portal,
}: {
  actions: readonly RibbonAction[];
  label: string;
  more: string;
  portal: HTMLElement;
}) {
  if (!actions.length) return null;
  return (
    <>
      <div className="od-ribbon-secondary">
        <Group label={label}>
          {actions.map((action) => (
            <Command
              key={action.label}
              label={action.label}
              icon={action.icon}
              disabled={!!action.disabled}
              pressed={action.pressed}
              action={action.run}
            />
          ))}
        </Group>
      </div>
      <div className="od-ribbon-more">
        <RibbonMenu
          actions={actions}
          label={more}
          group={label}
          portal={portal}
          className="od-command"
        >
          <Icon name="more-horizontal" />
          <span>{more}</span>
          <Icon name="chevron-down" />
        </RibbonMenu>
      </div>
    </>
  );
}

export function EditorRibbon<E extends EditorHost>({
  controller,
  state,
  panel,
  portal,
  editDisabled,
}: {
  controller: EditorController<E>;
  state: UiSnapshot<E>;
  panel?: PanelProps<E> | undefined;
  portal: HTMLElement;
  editDisabled: boolean;
}) {
  const [tab, setTab] = useState("edit");
  const [collapsed, setCollapsed] = useState(false);
  const t = messages(state.locale);
  const { file, document: snapshot } = state;
  const product = controller.product;
  const tabs: readonly RibbonTab[] = product.tabs?.(panel) ?? [
    { id: "edit", label: product.readLabel ? "read" : "edit" },
    { id: "view", label: "view", readOnly: true },
    ...(product.extraTabs
      ? ([
          { id: "pages", label: "pages" },
          { id: "annotations", label: "annotations" },
        ] as const)
      : []),
  ];
  const visible = tabs.filter(
    (entry) => state.mode === "edit" || entry.id === "edit" || entry.readOnly,
  );
  const active = visible.some((entry) => entry.id === tab)
    ? tab
    : (visible[0]?.id ?? "edit");
  return (
    <Tabs.Root
      value={active}
      onValueChange={(value) => {
        if (typeof value === "string") setTab(value);
      }}
    >
      <div className="od-tabs">
        <FileMenu
          key={snapshot?.documentId}
          controller={controller}
          state={state}
          portal={portal}
          actions={panel && product.fileActions?.(panel)}
        />
        <Tabs.List className="od-tab-list" aria-label={t.edit}>
          {visible.map(({ id, label, contextual }) => (
            <Tabs.Tab
              key={id}
              value={id}
              className={contextual ? "od-tab-contextual" : undefined}
            >
              {t[label]}
            </Tabs.Tab>
          ))}
        </Tabs.List>
        <button
          type="button"
          className="od-collapse"
          aria-label={collapsed ? t.expand : t.collapse}
          aria-expanded={!collapsed}
          onClick={() => setCollapsed(!collapsed)}
        >
          <Icon name={collapsed ? "chevron-down" : "chevron-up"} />
        </button>
      </div>
      {!collapsed &&
        file &&
        panel &&
        visible.map(({ id }) => (
          <Tabs.Panel
            key={id}
            value={id}
            data-format={product.format}
            className={
              product.tabs ? "od-ribbon od-ribbon-compact" : "od-ribbon"
            }
          >
            {id === "edit" && (
              <>
                <ClipboardGroup
                  key={snapshot?.documentId}
                  controller={controller}
                  state={state}
                  file={file}
                  portal={portal}
                  disabled={panel.disabled || !!snapshot?.stopped}
                />
                {state.mode === "edit" && !product.tabs && (
                  <Group label={t.history}>
                    <EditorCommandButton id="undo" />
                    <EditorCommandButton id="redo" />
                  </Group>
                )}
              </>
            )}
            {id === "view" && (
              <>
                {product.render("navigation", panel) ?? (
                  <Navigation {...panel} />
                )}
                <Group label={t.zoom}>
                  <Zoom {...panel} />
                </Group>
              </>
            )}
            {(id !== "edit" || state.mode === "edit" || !!product.tabs) &&
              product.render(id, {
                ...panel,
                disabled:
                  id === "view"
                    ? panel.disabled
                    : id === "edit" && !product.editReadOnly
                      ? panel.disabled || !!snapshot?.stopped
                      : editDisabled,
              })}
            {id === "view" && (
              <Group label={t.refresh}>
                <Command
                  label={snapshot?.stopped ? t.recover : t.refresh}
                  icon="refresh"
                  disabled={panel.disabled}
                  action={() => controller.run(() => file.recover())}
                />
              </Group>
            )}
          </Tabs.Panel>
        ))}
    </Tabs.Root>
  );
}

export function EditorSurface<E extends EditorHost>({
  controller,
  panel,
  portal,
}: {
  controller: EditorController<E>;
  panel?: PanelProps<E> | undefined;
  portal: HTMLElement;
}) {
  const target = useRef<CommandTarget | undefined>(undefined);
  const returnFocus = useRef<HTMLElement | null>(null);
  const node = (
    <NativeSlot node={controller.surfaces} className="od-surfaces" />
  );
  if (!controller.product.contextActions) return node;
  const actions = panel ? controller.product.contextActions(panel) : [];
  const t = messages(panel?.state.locale ?? "en-US");
  const commands = controller.commands;
  const snapshot = panel?.state.document;
  return (
    <ContextMenu.Root
      onOpenChange={(open) => {
        if (open) target.current = commands.captureTarget();
      }}
    >
      <ContextMenu.Trigger
        className="od-context-surface"
        onContextMenu={(event) => {
          const root = event.currentTarget.getRootNode();
          const active =
            root instanceof ShadowRoot
              ? root.activeElement
              : document.activeElement;
          returnFocus.current =
            active instanceof HTMLElement &&
            event.currentTarget.contains(active)
              ? active
              : null;
        }}
        onKeyDown={(event) => {
          if (
            event.key !== "ContextMenu" &&
            !(event.shiftKey && event.key === "F10")
          )
            return;
          if (event.nativeEvent.isComposing || snapshot?.composition) return;
          event.preventDefault();
          const anchor =
            event.target instanceof Element
              ? event.target
              : event.currentTarget;
          const rect = anchor.getBoundingClientRect();
          event.currentTarget.dispatchEvent(
            new MouseEvent("contextmenu", {
              bubbles: true,
              cancelable: true,
              composed: true,
              clientX: rect.left,
              clientY: rect.bottom,
            }),
          );
        }}
      >
        {node}
      </ContextMenu.Trigger>
      <ContextMenu.Portal container={portal}>
        <ContextMenu.Positioner className="od-menu-positioner">
          <ContextMenu.Popup
            className="od-menu"
            aria-label={t.contextActions}
            finalFocus={() => returnFocus.current ?? true}
          >
            {[
              "copy",
              ...(panel?.state.mode === "edit" ? ["undo", "redo"] : []),
            ].map((id) => {
              const state = commands.getSnapshot(id);
              if (!state) return null;
              return (
                <ContextMenu.Item
                  key={id}
                  disabled={!state.enabled || !!snapshot?.busy}
                  onClick={() =>
                    void commands.execute(id, target.current).catch(() => {})
                  }
                >
                  {state.icon && <Icon name={state.icon} />}
                  {state.label}
                </ContextMenu.Item>
              );
            })}
            {actions.map((action) => (
              <ContextMenu.Item
                key={action.label}
                disabled={!!action.disabled}
                onClick={action.run}
              >
                <Icon name={action.icon} />
                {action.label}
              </ContextMenu.Item>
            ))}
          </ContextMenu.Popup>
        </ContextMenu.Positioner>
      </ContextMenu.Portal>
    </ContextMenu.Root>
  );
}

export interface EditorPanelProps {
  label: string;
  /** Header icon; use the icon of the command that opens the panel. */
  icon?: IconName | undefined;
  closeLabel: string;
  closeDisabled?: boolean;
  close(): void;
  children: ReactNode;
}

export function EditorPanel({
  label,
  icon,
  closeLabel,
  closeDisabled,
  close,
  children,
}: EditorPanelProps) {
  const header = useRef<HTMLElement>(null);
  useLayoutEffect(() => {
    header.current?.focus({ preventScroll: true });
  }, []);
  // Headings that repeat the panel title stay for assistive technology only.
  useLayoutEffect(() => {
    const panel = header.current?.parentElement;
    if (!panel) return;
    for (const heading of panel.querySelectorAll(
      ":scope > :not(.od-task-header) :is(h2, h3, h4, legend, .od-group-label), :scope > :is(h2, h3, h4)",
    ))
      heading.classList.toggle(
        "od-repeat-heading",
        heading.textContent?.trim() === label.trim(),
      );
  });
  return (
    <aside
      className="od-properties od-task-panel"
      aria-label={label}
      onKeyDown={(event) => {
        if (
          event.key === "Escape" &&
          !event.defaultPrevented &&
          !closeDisabled
        ) {
          event.stopPropagation();
          close();
        }
      }}
    >
      <header className="od-task-header" tabIndex={-1} ref={header}>
        {icon && (
          <span className="od-task-icon" aria-hidden="true">
            <Icon name={icon} />
          </span>
        )}
        <strong>{label}</strong>
        <button
          type="button"
          aria-label={closeLabel}
          disabled={closeDisabled}
          onClick={close}
        >
          <Icon name="close" />
        </button>
      </header>
      {children}
    </aside>
  );
}
