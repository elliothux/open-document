import { useRef, useState } from "react";
import { Popover } from "@base-ui/react/popover";
import { Icon } from "./icons.js";
import type { CommandTarget, EditorCommandApi } from "./commands.js";

const rows = 8;
const columns = 8;

export interface EditorTablePickerProps {
  commands: Pick<EditorCommandApi, "captureTarget">;
  portal: HTMLElement;
  label: string;
  gridLabel: string;
  describe(rows: number, columns: number): string;
  disabled: boolean;
  insert(rows: number, columns: number, target: CommandTarget): void;
}

export function EditorTablePicker({
  commands,
  portal,
  label,
  gridLabel,
  describe,
  disabled,
  insert,
}: EditorTablePickerProps) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState([1, 1]);
  const [focus, setFocus] = useState([1, 1]);
  const buttons = useRef(new Map<string, HTMLButtonElement>());
  const first = useRef<HTMLButtonElement>(null);
  const target = useRef<CommandTarget | undefined>(undefined);
  const choose = (row: number, column: number) => {
    const captured = target.current;
    target.current = undefined;
    setOpen(false);
    if (captured && !disabled) insert(row, column, captured);
  };
  return (
    <Popover.Root
      modal={false}
      open={open}
      onOpenChange={(next) => {
        target.current = next ? commands.captureTarget() : undefined;
        if (next) {
          setActive([1, 1]);
          setFocus([1, 1]);
        }
        setOpen(next);
      }}
    >
      <Popover.Trigger className="od-command" disabled={disabled}>
        <Icon name="table-plus" />
        <span>{label}</span>
      </Popover.Trigger>
      <Popover.Portal container={portal}>
        <Popover.Positioner
          className="od-menu-positioner"
          align="start"
          sideOffset={4}
        >
          <Popover.Popup
            className="od-menu od-table-picker"
            initialFocus={first}
          >
            <Popover.Title className="od-dialog-title">{label}</Popover.Title>
            <Popover.Description>
              {describe(active[0] ?? 1, active[1] ?? 1)}
            </Popover.Description>
            <div role="grid" aria-label={gridLabel} className="od-table-grid">
              {Array.from({ length: rows }, (_, y) => (
                <div key={y} role="row">
                  {Array.from({ length: columns }, (_, x) => {
                    const row = y + 1,
                      column = x + 1;
                    const key = row + ":" + column;
                    const filled =
                      row <= (active[0] ?? 1) && column <= (active[1] ?? 1);
                    return (
                      <div key={key} role="gridcell" aria-selected={filled}>
                        <button
                          type="button"
                          aria-label={describe(row, column)}
                          tabIndex={
                            row === focus[0] && column === focus[1] ? 0 : -1
                          }
                          ref={(node) => {
                            if (row === 1 && column === 1) first.current = node;
                            if (node) buttons.current.set(key, node);
                            else buttons.current.delete(key);
                          }}
                          onPointerEnter={() => setActive([row, column])}
                          onFocus={() => {
                            setFocus([row, column]);
                            setActive([row, column]);
                          }}
                          onKeyDown={(event) => {
                            let nextRow = row,
                              nextColumn = column;
                            switch (event.key) {
                              case "ArrowDown":
                                nextRow = Math.min(rows, row + 1);
                                break;
                              case "ArrowUp":
                                nextRow = Math.max(1, row - 1);
                                break;
                              case "ArrowRight":
                                nextColumn = Math.min(columns, column + 1);
                                break;
                              case "ArrowLeft":
                                nextColumn = Math.max(1, column - 1);
                                break;
                              default:
                                return;
                            }
                            event.preventDefault();
                            buttons.current
                              .get(nextRow + ":" + nextColumn)
                              ?.focus();
                          }}
                          onClick={() => choose(row, column)}
                        />
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}
