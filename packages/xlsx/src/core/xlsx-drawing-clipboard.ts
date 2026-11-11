export interface XlsxDrawingClipboard {
  fragment: string;
  text: string;
}

export function checkDrawingFragment(
  value: unknown,
  maxUnits: number,
): asserts value is string {
  if (
    typeof value !== "string" ||
    !value ||
    value.length > maxUnits ||
    !value.isWellFormed()
  )
    throw new Error("Invalid drawing clipboard fragment");
}
