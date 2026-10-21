import type { FoundationClient } from "./foundation.js";

export async function cancelDocxPictureGesture(client: FoundationClient) {
  const state = await client.editState();
  return state.pictureGestureId === null
    ? state
    : client.pictureGesture(state.revision, {
        action: "cancel",
        id: state.pictureGestureId,
      });
}

export async function recoverDocxState(
  client: FoundationClient,
  revision: number,
  undo: boolean,
  assertOpen: () => void,
) {
  const state = await cancelDocxPictureGesture(client);
  assertOpen();
  if (undo && state.revision !== revision)
    throw new Error("Document changed outside the editor; resume before undo");
  if (undo && !state.canUndo) throw new Error("There is no edit to undo");
  const result = undo ? await client.undoDocx(state.revision) : state;
  assertOpen();
  return result;
}
