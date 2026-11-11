import { useRef, useState } from "react";
import { Popover } from "@base-ui/react/popover";
import { Icon } from "./icons.js";

export interface EditorSymbolPickerProps {
  /** Accessible name of the trigger. */
  readonly label: string;
  /** Visible trigger text and popover title. */
  readonly title: string;
  /** Accessible name of the symbol grid. */
  readonly gridLabel: string;
  readonly symbols: readonly string[];
  readonly disabled: boolean;
  readonly portal: HTMLElement;
  insert(symbol: string): void;
}

/** A trigger that opens a grid of symbols; choosing one closes the grid and inserts it. */
export function EditorSymbolPicker({
  label,
  title,
  gridLabel,
  symbols,
  disabled,
  portal,
  insert,
}: EditorSymbolPickerProps) {
  const [open, setOpen] = useState(false);
  // The host moves focus back to the document after an insertion.
  const inserted = useRef(false);
  return (
    <Popover.Root
      open={open}
      onOpenChange={(next) => {
        if (next) inserted.current = false;
        setOpen(next);
      }}
    >
      <Popover.Trigger
        className="od-command"
        disabled={disabled}
        aria-label={label}
      >
        <Icon name="special-character" />
        <span>{title}</span>
        <Icon name="chevron-down" />
      </Popover.Trigger>
      <Popover.Portal container={portal}>
        <Popover.Positioner
          className="od-menu-positioner"
          align="start"
          sideOffset={4}
        >
          <Popover.Popup
            className="od-menu"
            finalFocus={() => !inserted.current}
          >
            <Popover.Title className="od-menu-label">{title}</Popover.Title>
            <div className="od-symbol-grid" role="group" aria-label={gridLabel}>
              {symbols.map((symbol) => (
                <button
                  type="button"
                  key={symbol}
                  title={symbol}
                  disabled={disabled}
                  onClick={() => {
                    inserted.current = true;
                    setOpen(false);
                    insert(symbol);
                  }}
                >
                  {symbol}
                </button>
              ))}
            </div>
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}
