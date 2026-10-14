/** Download one completed output and release its platform URL on every path. */
export function downloadBytes(
  bytes: Uint8Array,
  type: string,
  filename: string,
): void {
  const url = URL.createObjectURL(
    new Blob([new Uint8Array(bytes).buffer], { type }),
  );
  const link = document.createElement("a");
  try {
    link.href = url;
    link.download = filename;
    link.click();
  } finally {
    URL.revokeObjectURL(url);
  }
}
