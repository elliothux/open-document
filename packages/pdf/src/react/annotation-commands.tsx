import { AnnotationTools } from "./annotations.js";
import type { PanelProps } from "./context.js";

export function AnnotationCommands({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const editor = file.editor;
  return (
    <AnnotationTools
      locale={state.locale}
      disabled={
        disabled || !!state.document?.draft || !!state.document?.composition
      }
      selected={editor.getSnapshot().data.property.startsWith("annotation:")}
      onEdit={() => controller.run(() => editor.beginAnnotationEdit())}
      onInk={(signature) => controller.run(() => editor.beginInk(signature))}
      onReply={() => controller.run(() => editor.beginAnnotationReply())}
      onDeleteThread={() =>
        controller.run(() => editor.deleteAnnotationThread())
      }
      onStamp={(file, signature) =>
        controller.run(async () => {
          if (file.size > 16777216)
            throw new Error("Stamp image exceeds budget");
          const result = await editor.insertStamp(
            new Uint8Array(await file.arrayBuffer()),
            signature,
          );
          const annotation = result.annotations.at(-1);
          if (annotation) {
            await editor.chooseProperty(`annotation:${annotation.id}`);
            await editor.beginAnnotationEdit();
          }
        })
      }
    />
  );
}
