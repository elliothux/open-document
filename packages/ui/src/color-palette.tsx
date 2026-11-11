import { useRef, useState } from "react";
import { Popover } from "@base-ui/react/popover";
import type { CommandTarget, EditorCommandApi } from "./commands.js";

const colors = [
  "000000",
  "434343",
  "666666",
  "999999",
  "CCCCCC",
  "FFFFFF",
  "B3261E",
  "E69138",
  "F1C232",
  "38761D",
  "134F5C",
  "0B5394",
  "351C75",
  "741B47",
  "CC0000",
  "274E13",
  "1155CC",
  "674EA7",
];

export interface EditorColorPaletteProps {
  commands: Pick<EditorCommandApi, "captureTarget">;
  label: string;
  custom: string;
  mixed: string;
  /** Six RGB hex digits, or null when the selection has mixed colors. */
  value: string | null;
  disabled: boolean;
  portal: HTMLElement;
  apply(color: string, target: CommandTarget): void;
}

export function EditorColorPalette({
  commands,
  label,
  custom,
  mixed,
  value,
  disabled,
  portal,
  apply,
}: EditorColorPaletteProps) {
  const [open, setOpen] = useState(false);
  const target = useRef<CommandTarget | undefined>(undefined);
  const choose = (color: string) => {
    const captured = target.current;
    target.current = undefined;
    setOpen(false);
    if (captured && !disabled) apply(color, captured);
  };
  return (
    <Popover.Root
      open={open}
      onOpenChange={(next) => {
        target.current = next ? commands.captureTarget() : undefined;
        setOpen(next);
      }}
    >
      <Popover.Trigger
        className="od-icon-command"
        disabled={disabled}
        aria-label={label}
        aria-description={value === null ? mixed : "#" + value}
        title={label}
      >
        <span
          className="od-color-chip"
          data-mixed={value === null || undefined}
          style={value === null ? undefined : { backgroundColor: "#" + value }}
        />
      </Popover.Trigger>
      <Popover.Portal container={portal}>
        <Popover.Positioner
          className="od-menu-positioner"
          align="start"
          sideOffset={4}
        >
          <Popover.Popup className="od-menu">
            <Popover.Title className="od-menu-label">{label}</Popover.Title>
            <div className="od-color-palette">
              {colors.map((color) => (
                <button
                  type="button"
                  key={color}
                  aria-label={"#" + color}
                  title={"#" + color}
                  aria-pressed={value?.toUpperCase() === color}
                  style={{ backgroundColor: "#" + color }}
                  onClick={() => choose(color)}
                />
              ))}
            </div>
            <label className="od-color-custom">
              {custom}
              <input
                type="color"
                value={"#" + (value ?? "000000")}
                onChange={(event) => choose(event.currentTarget.value.slice(1))}
              />
            </label>
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}
