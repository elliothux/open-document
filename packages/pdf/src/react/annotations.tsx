import { Group, Command } from "@open-document/ui/controls";

export function AnnotationTools(props: {
  locale: "zh-CN" | "en-US";
  disabled: boolean;
  selected: boolean;
  onEdit: () => void;
  onInk: (signature: boolean) => void;
  onStamp: (file: File, signature: boolean) => void;
  onReply: () => void;
  onDeleteThread: () => void;
}) {
  const zh = props.locale === "zh-CN";
  return (
    <Group
      label={zh ? "批注与签名外观" : "Annotations and signature appearances"}
    >
      <Command
        label={zh ? "墨迹" : "Ink"}
        disabled={props.disabled}
        action={() => props.onInk(false)}
      />
      <Command
        label={zh ? "手写签名" : "Handwritten signature"}
        disabled={props.disabled}
        action={() => props.onInk(true)}
      />
      {[false, true].map((signature) => (
        <label className="od-command" key={String(signature)}>
          {zh
            ? signature
              ? "图片签名"
              : "图片印章"
            : signature
              ? "Image signature"
              : "Image stamp"}
          <input
            type="file"
            accept="image/png,image/jpeg,image/webp"
            disabled={props.disabled}
            onChange={(event) => {
              const file = event.currentTarget.files?.[0];
              event.currentTarget.value = "";
              if (!file) return;
              props.onStamp(file, signature);
            }}
          />
        </label>
      ))}
      <Command
        label={zh ? "批注位置与样式" : "Annotation position and style"}
        disabled={props.disabled || !props.selected}
        action={props.onEdit}
      />
      <Command
        label={zh ? "回复批注" : "Reply to annotation"}
        disabled={props.disabled || !props.selected}
        action={props.onReply}
      />
      <Command
        label={zh ? "删除整条回复线程" : "Delete whole reply thread"}
        disabled={props.disabled || !props.selected}
        action={props.onDeleteThread}
      />
      <p role="note">
        {zh
          ? "签名仅为可见外观，不包含证书签署。"
          : "Signatures are visual appearances without certificate signing."}
      </p>
    </Group>
  );
}
