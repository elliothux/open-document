///|
#derive(@json.FromJson)
priv struct ClipboardRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  cut : Bool
}

///|
#derive(@json.FromJson)
priv struct FragmentRequest {
  revision : @common.RequestInt
  fragment : String
  preparePixels : Bool?
}

///|
#derive(@json.FromJson)
priv struct MarkupImagesRequest {
  revision : @common.RequestInt
  kind : String
  input : String
  mode : String
  preparePixels : Bool?
}

///|
#derive(@json.FromJson)
priv struct PasteHtmlRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  html : String
  profile : @common.RequestProfile
  mode : String
}

///|
#derive(@json.FromJson)
priv struct PasteMarkdownRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  markdown : String
  profile : @common.RequestProfile
  mode : String
}

///|
#derive(@json.FromJson)
priv struct PasteFragmentRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  fragment : String
  profile : @common.RequestProfile
}

///|
let clipboard_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "selectedText": (context, session, input) => {
    let command : ClipboardRequest = @common.request(input)
    Json(
      session.selected_text(
        command.revision.value,
        command.selection.selection(),
        cut=command.cut,
        layout?=context.layout,
      ),
    )
  },
  "tableClipboard": (context, session, input) => {
    let command : ClipboardRequest = @common.request(input)
    session.table_clipboard(
      command.revision.value,
      command.selection.selection(),
      cut=command.cut,
      layout?=context.layout,
    )
  },
  "docxClipboard": (context, session, input) => {
    let command : ClipboardRequest = @common.request(input)
    session.clipboard(
      command.revision.value,
      command.selection.selection(),
      cut=command.cut,
      layout?=context.layout,
    )
  },
  "tableFragmentImages": (context, session, input) => {
    let command : FragmentRequest = @common.request(input)
    session.table_fragment_images(
      command.revision.value,
      command.fragment,
      encode_image=bytes => Json(context.output.add(bytes)),
      prepare_pixels=command.preparePixels.unwrap_or(false),
    )
  },
  "bodyFragmentImages": (context, session, input) => {
    let command : FragmentRequest = @common.request(input)
    session.body_fragment_images(
      command.revision.value,
      command.fragment,
      encode_image=bytes => Json(context.output.add(bytes)),
      prepare_pixels=command.preparePixels.unwrap_or(false),
    )
  },
  "markupImages": (context, session, input) => {
    let command : MarkupImagesRequest = @common.request(input)
    session.markup_images(
      command.revision.value,
      command.kind,
      command.input,
      mode=command.mode,
      encode_image=bytes => Json(context.output.add(bytes)),
      prepare_pixels=command.preparePixels.unwrap_or(false),
    )
  },
  "pasteHtml": (context, session, input) => {
    let command : PasteHtmlRequest = @common.request(input)
    context.clear_edit_layout(
      session.paste_html(
        command.revision.value,
        command.selection.selection(),
        command.html,
        context.probe,
        command.profile.value,
        images=Some(context.images),
        mode=command.mode,
      ),
    )
  },
  "pasteMarkdown": (context, session, input) => {
    let command : PasteMarkdownRequest = @common.request(input)
    context.clear_edit_layout(
      session.paste_markdown(
        command.revision.value,
        command.selection.selection(),
        command.markdown,
        context.probe,
        command.profile.value,
        images=Some(context.images),
        mode=command.mode,
      ),
    )
  },
  "pasteBodyFragment": (context, session, input) => {
    let command : PasteFragmentRequest = @common.request(input)
    context.clear_edit_layout(
      session.paste_body_fragment(
        command.revision.value,
        command.selection.selection(),
        command.fragment,
        context.probe,
        command.profile.value,
        images=Some(context.images),
      ),
    )
  },
}
