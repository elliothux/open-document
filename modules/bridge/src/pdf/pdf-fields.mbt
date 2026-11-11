///|
#derive(@json.FromJson)
priv struct FieldOptionRequest {
  value : String
  label : String
}

///|
priv struct FieldOptions {
  value : Array[(String, String)]
}

///|
impl @json.FromJson for FieldOptions with fn from_json(input, path) {
  guard input is Array(options) && options.length() <= @model.FieldOptionCount else {
    raise @json.JsonDecodeError((path, "Bounded field options are required"))
  }
  let value = options.map(option => {
    let parsed : FieldOptionRequest = @json.from_json(option, path~)
    (parsed.value, parsed.label)
  })
  { value, }
}

///|
#derive(@json.FromJson)
priv struct FieldSpecRequest {
  name : String
  tooltip : String
  kind : String
  placement : PlacementRequest
  options : FieldOptions
  value : Json
  defaultValue : Json
  readOnly : Bool
  required : Bool
  multiline : Bool
  multiSelect : Bool
  maxLength : @common.RequestInt
  font : String
  size : @common.RequestNumber
  color : String
  background : String
  border : @common.RequestNumber
}

///|
fn FieldSpecRequest::spec(self : FieldSpecRequest) -> @model.PdfFieldDesign {
  {
    name: self.name,
    tooltip: self.tooltip,
    kind: self.kind,
    placement: self.placement.placement(),
    options: self.options.value,
    value: self.value,
    defaultValue: self.defaultValue,
    readOnly: self.readOnly,
    required: self.required,
    multiline: self.multiline,
    multiSelect: self.multiSelect,
    maxLength: self.maxLength.value,
    font: self.font,
    size: self.size.value,
    color: self.color,
    background: self.background,
    border: self.border.value,
  }
}

///|
#derive(@json.FromJson)
priv struct FieldWidgetRequest {
  id : String
  page : String
  placement : PlacementRequest
  border : @common.RequestNumber
  borderColor : String
  background : String
  exportValue : String
}

///|
fn FieldWidgetRequest::widget(
  self : FieldWidgetRequest,
) -> @model.PdfFieldWidgetDesign {
  {
    id: self.id,
    page: self.page,
    placement: self.placement.placement(),
    border: self.border.value,
    borderColor: self.borderColor,
    background: self.background,
    exportValue: self.exportValue,
  }
}

///|
priv struct FieldWidgets {
  value : Array[@model.PdfFieldWidgetDesign]
}

///|
impl @json.FromJson for FieldWidgets with fn from_json(input, path) {
  guard input is Array(widgets) && widgets.length() <= @model.FieldWidgetCount else {
    raise @json.JsonDecodeError((path, "Bounded field widgets are required"))
  }
  let value = widgets.map(widget => {
    let parsed : FieldWidgetRequest = @json.from_json(widget, path~)
    parsed.widget()
  })
  { value, }
}

///|
#derive(@json.FromJson)
priv struct FieldRequest {
  revision : @common.RequestInt
  field : String
}

///|
#derive(@json.FromJson)
priv struct FieldNameRequest {
  revision : @common.RequestInt
  field : String
  name : String
}

///|
#derive(@json.FromJson)
priv struct DuplicateFieldRequest {
  revision : @common.RequestInt
  field : String
  name : String
  dx : @common.RequestNumber
  dy : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct CreateFieldRequest {
  revision : @common.RequestInt
  page : String
  spec : FieldSpecRequest
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct UpdateFieldRequest {
  revision : @common.RequestInt
  field : String
  spec : FieldSpecRequest
  widgets : FieldWidgets
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct FieldValueRequest {
  revision : @common.RequestInt
  field : String
  value : Json
  profile : @common.RequestProfile
}

///|
let field_handlers : Map[
  String,
  (Context, @model.PdfSession, Json) -> String raise @failure.Failure,
] = {
  "pdfFieldDesign": (_context, session, input) => {
    let command : FieldRequest = @common.request(input)
    ToJson::to_json(session.field_design(command.revision.value, command.field)).stringify()
  },
  "createPdfField": (context, session, input) => {
    let command : CreateFieldRequest = @common.request(input)
    session
    .create_field(
      command.revision.value,
      command.page,
      command.spec.spec(),
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
  "updatePdfFieldDesign": (context, session, input) => {
    let command : UpdateFieldRequest = @common.request(input)
    session
    .update_field_design(
      command.revision.value,
      command.field,
      command.spec.spec(),
      command.widgets.value,
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
  "renamePdfField": (_context, session, input) => {
    let command : FieldNameRequest = @common.request(input)
    session
    .rename_field(command.revision.value, command.field, command.name)
    .stringify()
  },
  "deletePdfField": (_context, session, input) => {
    let command : FieldRequest = @common.request(input)
    session.delete_field(command.revision.value, command.field).stringify()
  },
  "duplicatePdfField": (_context, session, input) => {
    let command : DuplicateFieldRequest = @common.request(input)
    session
    .duplicate_field(
      command.revision.value,
      command.field,
      command.name,
      command.dx.value,
      command.dy.value,
    )
    .stringify()
  },
  "setPdfFieldValue": (context, session, input) => {
    let command : FieldValueRequest = @common.request(input)
    session
    .set_field(
      command.revision.value,
      command.field,
      command.value,
      context.probe,
      command.profile.value,
    )
    .stringify()
  },
}
