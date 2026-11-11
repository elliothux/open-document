import { DocumentError } from "@open-document/wasm";

export const viewOnlyReason = "This editor is in view mode";
export function viewOnlyError(): DocumentError {
  return new DocumentError("read-only-view", viewOnlyReason, "", -1);
}

export function checkViewCommand<T extends string>(
  readOnly: boolean,
  allowed: ReadonlySet<T>,
  operation: T,
): void {
  if (readOnly && !allowed.has(operation)) throw viewOnlyError();
}
