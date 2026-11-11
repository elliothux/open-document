///|
#derive(@json.FromJson)
priv struct PageSectionRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct RunningAreaRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  kind : String
  variant : String
}

///|
#derive(@json.FromJson)
priv struct RunningLinkRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  kind : String
  variant : String
  linked : Bool
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct RunningOptionsRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  first : Bool
  even : Bool
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct SetRunningAreaRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  kind : String
  variant : String
  content : RunningContentRequest
  distance : @common.RequestNumber
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct SetPageSetupRequest {
  revision : @common.RequestInt
  page : PageSetupInput
}

///|
#derive(@json.FromJson)
priv struct ReferenceEditRequest {
  revision : @common.RequestInt
  change : Json
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct CaptionCommandRequest {
  revision : @common.RequestInt
  caption : CaptionInput
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct CaptionRequest {
  label : String
  text : String
  position : String
  format : String?
  chapter : CaptionChapterRequest?
}

///|
#derive(@json.FromJson)
priv struct CaptionChapterRequest {
  level : @common.RequestInt
  separator : String
}

///|
priv struct CaptionInput {
  value : CaptionRequest
}

///|
impl @json.FromJson for CaptionInput with fn from_json(input, path) {
  guard input is Object(fields) &&
    fields.length() >= 3 &&
    fields.length() <= 5 &&
    fields
    .keys()
    .all(key => ["label", "text", "position", "format", "chapter"].contains(key)) else {
    raise @json.JsonDecodeError((path, "Invalid caption fields"))
  }
  guard !(input is { "format": Null, .. }) else {
    raise @json.JsonDecodeError(
      (path.add_key("format"), "Invalid caption format"),
    )
  }
  if fields.get("chapter") is Some(chapter) {
    guard chapter is Object(fields) && fields.length() == 2 else {
      raise @json.JsonDecodeError(
        (path.add_key("chapter"), "Invalid caption chapter fields"),
      )
    }
  }
  { value: @json.from_json(input, path~), }
}

///|
#derive(@json.FromJson)
priv struct DocumentProtectionRequest {
  revision : @common.RequestInt
  enabled : Bool
  password : String
  passwordSalt : String
}

///|
#derive(@json.FromJson)
priv struct SectionBreakRequest {
  revision : @common.RequestInt
  kind : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct PageProfileRequest {
  revision : @common.RequestInt
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct CoverPageRequest {
  revision : @common.RequestInt
  cover : @common.RequiredNullable[CoverPageInput]
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct CoverPageInput {
  title : String
  subtitle : String
}

///|
#derive(@json.FromJson)
priv struct PageColumnsRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  columns : @common.RequiredNullable[PageColumnsInput]
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct PageNumberingRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  numbering : @common.RequiredNullable[PageNumberingInput]
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct PageBackgroundRequest {
  revision : @common.RequestInt
  color : @common.RequiredNullable[String]
}

///|
#derive(@json.FromJson)
priv struct SetWatermarkRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  value : Json
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct PageBordersRequest {
  revision : @common.RequestInt
  section : @common.RequestInt
  borders : @common.RequiredNullable[PageBordersInput]
}

///|
let page_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "docxSources": (_context, session, request) => {
    let revision = @common.request_revision(request)
    session.bibliography_sources(revision)
  },
  "docxIndexes": (_context, session, request) => {
    let revision = @common.request_revision(request)
    session.indexes(revision)
  },
  "docxTableOfContents": (_context, session, request) => {
    let revision = @common.request_revision(request)
    session.table_of_contents(revision)
  },
  "documentProtection": (_context, session, request) => {
    let revision = @common.request_revision(request)
    session.document_protection(revision)
  },
  "bodyPageField": (_context, session, request) => {
    let command : RevisionSelectionRequest = @common.request(request)
    session.body_page_field(
      command.revision.value,
      command.selection.selection(),
    )
  },
  "runningArea": (_context, session, request) => {
    let command : RunningAreaRequest = @common.request(request)
    session.running_area(
      command.revision.value,
      command.section.value,
      command.kind,
      command.variant,
    )
  },
  "pageSetup": (_context, session, request) => {
    let command : PageSectionRequest = @common.request(request)
    session.page_setup(command.revision.value, section=command.section.value)
  },
  "setCoverPage": (self, session, request) => {
    if request is { "cover": cover, .. } {
      guard cover is Null || (cover is Object(fields) && fields.length() == 2) else {
        @failure.reject("invalid-operation", "Invalid cover page fields")
      }
    }
    let command : CoverPageRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_cover_page(
      revision,
      command.cover.value.map(cover => cover.title),
      command.cover.value.map(cover => cover.subtitle).unwrap_or(""),
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setDocumentProtection": (self, session, request) => {
    let command : DocumentProtectionRequest = @common.request(request)
    let revision = command.revision.value
    let result = {
      let salt = @common.byte_input(command.passwordSalt, 24) catch {
        _ =>
          @failure.reject(
            "invalid-operation", "Invalid document protection salt",
          )
      }
      session.set_document_protection(
        revision,
        command.enabled,
        command.password,
        salt,
      )
    }
    self.clear_edit_layout(result, previous=revision)
  },
  "editDocxTableOfContents": (self, session, request) => {
    let command : ReferenceEditRequest = @common.request(request)
    let revision = command.revision.value
    let change = command.change
    let result = {
      guard change is Object(fields) && fields.length() == 2 else {
        @failure.reject(
          "invalid-operation", "Invalid table of contents command",
        )
      }
      let edit = match change {
        { "action": String("insert"), "levels": value, .. } => {
          let levels : @common.RequestInt = @common.request(value)
          @model.TocEdit::InsertToc(levels.value)
        }
        { "action": String("insertCaptions"), "sequence": String(sequence), .. } =>
          @model.TocEdit::InsertCaptionToc(sequence)
        {
          "action": String("update" | "delete" as action),
          "paragraph": value,
          ..
        } => {
          let paragraph : @common.RequestInt = @common.request(value)
          if action == "update" {
            @model.TocEdit::UpdateToc(paragraph.value)
          } else {
            @model.TocEdit::DeleteToc(paragraph.value)
          }
        }
        _ =>
          @failure.reject(
            "invalid-operation", "Invalid table of contents fields",
          )
      }
      session.edit_table_of_contents(
        revision,
        edit,
        probe=self.probe,
        profile=command.profile.value,
        images=self.images,
      )
    }
    self.clear_edit_layout(result, previous=revision)
  },
  "editDocxBibliography": (self, session, request) => {
    let command : ReferenceEditRequest = @common.request(request)
    let revision = command.revision.value
    let change = command.change
    let result = {
      guard change is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid bibliography command")
      }
      let edit = match change {
        { "action": String("insert"), "title": String(title), .. } =>
          @model.BibliographyFieldEdit::InsertBibliography(title)
        {
          "action": String("update" | "delete" as action),
          "paragraph": value,
          ..
        } => {
          let paragraph : @common.RequestInt = @common.request(value)
          if action == "update" {
            @model.BibliographyFieldEdit::UpdateBibliography(paragraph.value)
          } else {
            @model.BibliographyFieldEdit::DeleteBibliography(paragraph.value)
          }
        }
        _ => @failure.reject("invalid-operation", "Invalid bibliography fields")
      }
      session.edit_bibliography(
        revision,
        edit,
        probe=self.probe,
        profile=command.profile.value,
        images=self.images,
      )
    }
    self.clear_edit_layout(result, previous=revision)
  },
  "editDocxCitation": (self, session, request) => {
    let command : ReferenceEditRequest = @common.request(request)
    let revision = command.revision.value
    let change = command.change
    let result = {
      guard change is Object(fields) else {
        @failure.reject("invalid-operation", "Invalid citation command")
      }
      match (change, fields.length()) {
        ({ "action": String("insert"), "tag": String(tag), .. }, 2) =>
          session.insert_citation(
            revision,
            tag,
            probe=self.probe,
            profile=command.profile.value,
            images=self.images,
          )
        ({ "action": String("update"), .. }, 1) =>
          session.update_citations(
            revision,
            probe=self.probe,
            profile=command.profile.value,
            images=self.images,
          )
        _ => @failure.reject("invalid-operation", "Invalid citation fields")
      }
    }
    self.clear_edit_layout(result, previous=revision)
  },
  "editDocxSource": (self, session, request) => {
    let command : RevisionChangeRequest = @common.request(request)
    let revision = command.revision.value
    let change = command.change
    let result = {
      guard change is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid source command")
      }
      let edit = match change {
        { "action": String("delete"), "tag": String(tag), .. } =>
          @model.BibliographyEdit::DeleteSource(tag)
        {
          "action": String("create" | "update" as action),
          "source": Object(data) as value,
          ..
        } if data.length() == 7 => {
          let source : @model.BibliographySource = @common.request(value)
          if action == "create" {
            @model.BibliographyEdit::CreateSource(source)
          } else {
            @model.BibliographyEdit::UpdateSource(source)
          }
        }
        _ => @failure.reject("invalid-operation", "Invalid source fields")
      }
      session.edit_bibliography_source(revision, edit)
    }
    self.clear_edit_layout(result, previous=revision)
  },
  "editDocxIndex": (self, session, request) => {
    let command : ReferenceEditRequest = @common.request(request)
    let revision = command.revision.value
    let change = command.change
    let result = {
      guard change is Object(fields) else {
        @failure.reject("invalid-operation", "Invalid index command")
      }
      let edit = match (change, fields.length()) {
        ({ "action": String("mark"), "label": String(label), .. }, 2) =>
          @model.IndexEdit::MarkIndexEntry(label)
        (
          {
            "action": String("updateEntry"),
            "id": value,
            "label": String(label),
            ..
          },
          3,
        ) => {
          let id : @common.RequestInt = @common.request(value)
          @model.IndexEdit::UpdateIndexEntry(id.value, label)
        }
        ({ "action": String("deleteEntry"), "id": value, .. }, 2) => {
          let id : @common.RequestInt = @common.request(value)
          @model.IndexEdit::DeleteIndexEntry(id.value)
        }
        ({ "action": String("insert"), .. }, 1) => @model.IndexEdit::InsertIndex
        (
          {
            "action": String("update" | "delete" as action),
            "paragraph": value,
            ..
          },
          2,
        ) => {
          let paragraph : @common.RequestInt = @common.request(value)
          if action == "update" {
            @model.IndexEdit::UpdateIndex(paragraph.value)
          } else {
            @model.IndexEdit::DeleteIndex(paragraph.value)
          }
        }
        _ =>
          @failure.reject("invalid-operation", "Invalid index command fields")
      }
      session.edit_index(
        revision,
        edit,
        probe=self.probe,
        profile=command.profile.value,
        images=self.images,
      )
    }
    self.clear_edit_layout(result, previous=revision)
  },
  "insertDocxCaption": (self, session, request) => {
    let command : CaptionCommandRequest = @common.request(request)
    let revision = command.revision.value
    let input = command.caption.value
    let result = {
      guard ["before", "after"].contains(input.position) else {
        @failure.reject("invalid-operation", "Invalid caption position")
      }
      let (chapterLevel, separator) = if input.chapter is Some(chapter) {
        let level = chapter.level.value
        guard level >= 1 && level <= 9 else {
          @failure.reject("invalid-operation", "Invalid caption chapter level")
        }
        (level, chapter.separator)
      } else {
        (0, "-")
      }
      session.insert_caption(
        revision,
        input.label,
        input.text,
        input.position == "before",
        input.format.unwrap_or(""),
        probe=self.probe,
        profile=command.profile.value,
        images=self.images,
        chapterLevel~,
        separator~,
      )
    }
    self.clear_edit_layout(result, previous=revision)
  },
  "insertSectionBreak": (self, session, request) => {
    let command : SectionBreakRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.insert_section_break(
      revision,
      command.kind,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "insertBodyPageField": (context, session, request) => {
    context.edit_page_field(session, request, false)
  },
  "editBodyPageField": (context, session, request) => {
    context.edit_page_field(session, request, true)
  },
  "updateBodyPageFields": (self, session, request) => {
    let command : PageProfileRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.update_body_page_fields(
      revision,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setPageColumns": (self, session, request) => {
    if request is { "columns": columns, .. } && !(columns is Null) {
      check_page_columns_fields(columns)
    }
    let command : PageColumnsRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_page_columns(
      revision,
      command.section.value,
      command.columns.value.map(PageColumnsInput::columns),
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setPageNumbering": (self, session, request) => {
    if request is { "numbering": numbering, .. } {
      guard numbering is Null ||
        (numbering is Object(fields) && fields.length() == 2) else {
        @failure.reject("invalid-operation", "Invalid page numbering")
      }
    }
    let command : PageNumberingRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_page_numbering(
      revision,
      command.section.value,
      command.numbering.value.map(PageNumberingInput::numbering),
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setRunningLink": (self, session, request) => {
    let command : RunningLinkRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_running_link(
      revision,
      command.section.value,
      command.kind,
      command.variant,
      command.linked,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setRunningOptions": (self, session, request) => {
    let command : RunningOptionsRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_running_options(
      revision,
      command.section.value,
      command.first,
      command.even,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setRunningArea": (self, session, request) => {
    let command : SetRunningAreaRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_running_area(
      revision,
      command.section.value,
      command.kind,
      command.variant,
      command.content.value,
      command.distance.value,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setPageSetup": (self, session, request) => {
    if request is { "page": page, .. } {
      check_page_setup_fields(page)
    }
    let command : SetPageSetupRequest = @common.request(request)
    let revision = command.revision.value
    let page = command.page
    let result = session.set_page_setup(
      revision,
      page.section.value,
      {
        width: page.width.value,
        height: page.height.value,
        top: page.top.value,
        right: page.right.value,
        bottom: page.bottom.value,
        left: page.left.value,
      },
      orientation=page.orientation,
      startType=page.startType,
      footnotesAt=page.footnotesAt,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setPageBackground": (self, session, request) => {
    let command : PageBackgroundRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_page_background(revision, command.color.value)
    self.clear_edit_layout(result, previous=revision)
  },
  "watermark": (_context, session, request) => {
    let command : PageSectionRequest = @common.request(request)
    session.watermark(command.revision.value, command.section.value)
  },
  "setWatermark": (self, session, request) => {
    let command : SetWatermarkRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_watermark(
      revision,
      command.section.value,
      watermark_value(command.value),
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    self.clear_edit_layout(result, previous=revision)
  },
  "setPageBorders": (self, session, request) => {
    if request is { "borders": borders, .. } && !(borders is Null) {
      check_page_border_fields(borders)
    }
    let command : PageBordersRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.set_page_borders(
      revision,
      command.section.value,
      command.borders.value.map(PageBordersInput::borders),
    )
    self.clear_edit_layout(result, previous=revision)
  },
}
