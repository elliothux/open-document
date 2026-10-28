/** Supply local wall-clock components; the core owns date-field formatting. */
export function presentationDateTime(value?: string): string {
  if (value === undefined) {
    const now = new Date();
    const pad = (n: number, width = 2) => String(n).padStart(width, "0");
    value = `${pad(now.getFullYear(), 4)}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
  }
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value) ||
    value.startsWith("0000")
  )
    throw new Error("Invalid presentation date and time");
  const parsed = new Date(value + "Z");
  if (
    !Number.isFinite(parsed.getTime()) ||
    parsed.toISOString().slice(0, 19) !== value
  )
    throw new Error("Invalid presentation date and time");
  return value;
}
