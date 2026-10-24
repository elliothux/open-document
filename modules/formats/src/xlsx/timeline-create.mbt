///|
pub(all) struct TimelineSettings {
  pivot : String
  field : Int
  name : String
  caption : String
  width : Double
  height : Double
}

///|
/// Inserts a native monthly timeline at the selection and reuses an existing field connection.
pub fn Session::insert_timeline(
  self : Session,
  revision : Int,
  sheet : String,
  settings : TimelineSettings,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  guard self.dimension_reason(current).is_empty() && current.state == "visible" else {
    @failure.reject(
      "protected-content", "Timeline destination is protected or hidden",
    )
  }
  check_picture_text(settings.name, settings.caption)
  guard !settings.caption.trim().is_empty() && settings.caption.length() <= 255 else {
    @failure.reject("invalid-name", "Timeline caption is invalid")
  }
  let uid = self.timeline_creation_identity(settings.name)
  let controls = self.read_timelines(sheet)
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let objects = self.sheet_objects(current, dimensions)
  guard controls.length() < 64 && objects.length() < 256 else {
    @failure.reject(
      "limit-exceeded", "Worksheet timeline or drawing count exceeds budget",
    )
  }
  let pivot = self
    .pivot_locations()
    .iter()
    .find_first(pivot => pivot.part == settings.pivot)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Timeline pivot is unavailable")
    })
  let (definition, records) = self.pivot_settings(pivot, shared=true)
  let range = definition.validate()
  guard settings.field >= 0 && settings.field <= range.right - range.left else {
    @failure.reject(
      "invalid-operation", "Timeline field is outside its pivot source",
    )
  }
  guard !definition.numberGroups.any(group => group.field == settings.field) else {
    @failure.reject(
      "protected-content", "Timeline fields cannot use numeric grouping",
    )
  }
  let data = self.cached_pivot(pivot, definition, records)
  let selection = if self.selection.0 == sheet {
    self.selection.1
  } else {
    Range::parse("A1")
  }
  let rect : @layout.Border = {
    x: dimensions.columns.position(selection.left),
    y: dimensions.rows.position(selection.top),
    width: settings.width,
    height: settings.height,
  }
  check_picture_rect("move", rect, dimensions)
  let id = for number in 1..<=16384 {
    let id = number.to_string()
    if !objects.any(object => object.id == id) {
      break id
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Timeline drawing identities exhausted")
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let (cache, workbook) = self.timeline_creation_cache(
    pivot,
    settings.field,
    definition,
    data,
    parts,
    created,
    edits,
  )
  let (_, relation) = self.create_sheet_resource(
    sheet,
    "Timeline",
    "<timelines xmlns='\{timeline_uri}'><timeline\{uid} name='\{escaped_attribute(encoded_text(settings.name))}' caption='\{escaped_attribute(encoded_text(settings.caption))}' cache='\{escaped_attribute(encoded_text(cache.name))}' level='2' selectionLevel='2' scrollPosition='\{cache.state.bounds.start}' style='TimelineStyleLight1'/></timelines>",
    parts,
    created,
    edits,
  )
  let (sheet_document, edit) = analysis_reference(
    current.document,
    timeline_view_extension,
    "timelineRefs",
    "timelineRef",
    relation,
    payload_uri=timeline_uri,
  )
  edits.push((sheet, edit))
  let (drawing, sheet_document) = match self.picture_drawing(current) {
    Some((part, _)) => (part, sheet_document)
    None => {
      let (part, relation) = self.create_sheet_resource(
        sheet,
        "drawing",
        "<xdr:wsDr xmlns:xdr='\{picture_uri}'/>",
        parts,
        created,
        edits,
      )
      let (document, edit) = insert_sheet_drawing(
        sheet_document,
        relation,
        name="drawing",
      )
      edits.push((sheet, edit))
      (part, document)
    }
  }
  let document = parts.get(drawing).unwrap_or_else(() => self.part_xml(drawing))
  let (document, edit) = document.edit_source([
    insertion(
      document.nodes()[0],
      picture_frame_source(
        "move",
        rect,
        timeline_graphic_source(id, settings.name, settings.caption, rect),
        dimensions,
      ),
    ),
  ])
  parts[drawing] = document
  edits.push((drawing, edit))
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    sheet,
    current.name,
    current.state,
    sheet_document,
    self.strings,
    self.styles.length(),
  )
  let candidate = { ..self, workbook, parts, sheets, }
  ignore(candidate.read_timelines(sheet))
  let objects = candidate.sheet_objects(sheets[index], dimensions)
  let object = objects.iter().find_first(object => object.id == id).unwrap()
  let painted : Array[@layout.PositionedPrimitive] = []
  object.paint(painted, object.rect, probe, profile)
  self.commit(
    sheets,
    workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}
