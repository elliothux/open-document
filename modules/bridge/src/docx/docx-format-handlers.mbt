///|
priv struct CatalogRequest {
  revision : @common.RequestInt
  kind : String
} derive(@json.FromJson)

///|
priv struct ThemeColorRequest {
  revision : @common.RequestInt
  slot : String
  color : String
} derive(@json.FromJson)

///|
priv struct ListLevelRequest {
  revision : @common.RequestInt
  listId : @common.RequestInt
  level : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct TabIntervalRequest {
  revision : @common.RequestInt
  interval : Json
} derive(@json.FromJson)

///|
priv struct CreateStyleRequest {
  revision : @common.RequestInt
  name : String
  kind : String
  basedOn : String?
} derive(@json.FromJson)

///|
priv struct DeleteStyleRequest {
  revision : @common.RequestInt
  key : String
  replacement : String
} derive(@json.FromJson)

///|
priv struct FormatSelectionRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  profile : @common.RequestProfile
  format : Json?
} derive(@json.FromJson)

///|
priv struct RevisionChangeRequest {
  revision : @common.RequestInt
  change : Json
} derive(@json.FromJson)

///|
priv struct ListEditRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  change : Json
} derive(@json.FromJson)

///|
priv struct HyperlinkEditRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
  target : @common.RequiredNullable[String]
  text : String?
} derive(@json.FromJson)

///|
let format_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "docxRuler": (context, session, input) => {
    context.docx_ruler(session, input, false)
  },
  "editDocxRuler": (context, session, input) => {
    context.docx_ruler(session, input, true)
  },
  "styleCatalog": (_context, session, input) => {
    let command : CatalogRequest = @common.request(input)
    session.style_catalog(command.revision.value, command.kind)
  },
  "docxThemeColors": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.theme_colors(revision)
  },
  "docxThemeFonts": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.theme_fonts(revision)
  },
  "setDocxThemeFonts": (context, session, input) => {
    context.docx_theme_fonts(session, input)
  },
  "setDocxThemeColor": (context, session, input) => {
    let command : ThemeColorRequest = @common.request(input)
    let revision = command.revision.value
    context.clear_edit_layout(
      session.set_theme_color(revision, command.slot, command.color),
      previous=revision,
    )
  },
  "listCatalog": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.list_catalog(revision)
  },
  "updateListLevel": (context, session, input) => {
    let command : ListLevelRequest = @common.request(input)
    context.clear_edit_layout(
      session.update_list_level(
        command.revision.value,
        command.listId.value,
        command.level.value,
        list_level_format(input),
      ),
    )
  },
  "editList": (context, session, input) => {
    let command : ListEditRequest = @common.request(input)
    context.clear_edit_layout(
      session.edit_list(
        command.revision.value,
        command.selection.selection(),
        list_edit(command.change),
      ),
    )
  },
  "setDefaultTabStop": (context, session, input) => {
    let command : TabIntervalRequest = @common.request(input)
    let interval = match command.interval {
      Null => None
      Number(value, ..) => Some(value)
      _ => @failure.reject("invalid-operation", "Invalid default tab interval")
    }
    context.clear_edit_layout(
      session.set_default_tab_stop(command.revision.value, interval),
    )
  },
  "createStyle": (context, session, input) => {
    let command : CreateStyleRequest = @common.request(input)
    context.clear_edit_layout(
      session.create_style(
        command.revision.value,
        command.name,
        command.kind,
        based_on=command.basedOn,
      ),
    )
  },
  "deleteStyle": (context, session, input) => {
    let command : DeleteStyleRequest = @common.request(input)
    context.clear_edit_layout(
      session.delete_style(
        command.revision.value,
        command.key,
        command.replacement,
      ),
    )
  },
  "captureFormat": (_context, session, input) => {
    let command : RevisionSelectionRequest = @common.request(input)
    session.capture_format(
      command.revision.value,
      command.selection.selection(),
    )
  },
  "applyFormat": (context, session, input) => {
    context.edit_docx_style(session, input, false)
  },
  "updateStyle": (context, session, input) => {
    context.edit_docx_style(session, input, true)
  },
  "editBookmark": (context, session, input) => {
    let command : RevisionChangeRequest = @common.request(input)
    let revision = command.revision.value
    context.clear_edit_layout(
      session.edit_bookmark(revision, bookmark_edit(command.change)),
      previous=revision,
    )
  },
  "editDocxComment": (context, session, input) => {
    let command : RevisionChangeRequest = @common.request(input)
    let revision = command.revision.value
    context.clear_edit_layout(
      session.edit_comment(revision, docx_comment_edit(command.change)),
      previous=revision,
    )
  },
  "setHyperlink": (context, session, input) => {
    guard !(input is { "text": Null, .. }) else {
      @failure.reject("invalid-operation", "Invalid hyperlink display text")
    }
    let command : HyperlinkEditRequest = @common.request(input)
    let revision = command.revision.value
    context.clear_edit_layout(
      session.set_hyperlink(
        revision,
        command.selection.selection(),
        command.target.value,
        text=command.text,
      ),
      previous=revision,
    )
  },
  "setCharacterFormat": (context, session, input) => {
    let command : FormatSelectionRequest = @common.request(input)
    let revision = command.revision.value
    context.clear_edit_layout(
      session.set_character_format(
        revision,
        command.selection.selection(),
        character_format(command.format.unwrap_or(Json::null())),
        probe=context.probe,
        profile=command.profile.value,
        images=context.images,
      ),
      previous=revision,
    )
  },
  "setParagraphFormat": (context, session, input) => {
    let command : FormatSelectionRequest = @common.request(input)
    let revision = command.revision.value
    context.clear_edit_layout(
      session.set_paragraph_format(
        revision,
        command.selection.selection(),
        paragraph_format(command.format.unwrap_or(Json::null())),
        probe=context.probe,
        profile=command.profile.value,
        images=context.images,
      ),
      previous=revision,
    )
  },
}
