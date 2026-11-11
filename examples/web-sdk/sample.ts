export async function loadSampleDocument(): Promise<File> {
  const url = new URL("../sample.docx", import.meta.url);
  const response = await fetch(url);
  if (!response.ok)
    throw new Error(`Cannot load sample.docx (${response.status})`);
  return new File([await response.arrayBuffer()], "sample.docx");
}
