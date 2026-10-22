///|
pub(all) struct SheetChartSettings {
  kind : String
  title : String
  label : String
  legend : String
  hole_size : Int?
  categories : String
  names : Array[String]
  values : Array[String]
}

///|
fn Session::chart_from_settings(
  self : Session,
  owner : String,
  settings : SheetChartSettings,
) -> @chart.WorksheetChart raise @failure.Failure {
  guard settings.names.length() >= 1 &&
    settings.names.length() <= 8 &&
    settings.names.length() == settings.values.length() else {
    @failure.reject(
      "invalid-chart", "Chart references require 1-8 matching series",
    )
  }
  let chart : @chart.WorksheetChart = {
    categories: settings.categories,
    names: settings.names,
    values: settings.values,
    data: {
      kind: settings.kind,
      title: settings.title,
      label: settings.label,
      legend: settings.legend,
      hole_size: settings.hole_size,
      categories: [""],
      series: settings.names.map(_ => { name: "Series", values: [None], }),
    },
  }
  self.resolved_chart(owner, chart, {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  })
}

///|
fn sheet_chart_settings(chart : @chart.WorksheetChart) -> SheetChartSettings {
  {
    kind: chart.data.kind,
    title: chart.data.title,
    label: chart.data.label,
    legend: chart.data.legend,
    hole_size: chart.data.hole_size,
    categories: chart.categories,
    names: chart.names,
    values: chart.values,
  }
}

///|
fn chart_transform(rect : @layout.Border) -> String {
  "<odXdr:xfrm xmlns:odXdr=\"\{picture_uri}\" xmlns:odA=\"\{picture_drawing_uri}\"><odA:off x=\"\{picture_emu(rect.x)}\" y=\"\{picture_emu(rect.y)}\"/><odA:ext cx=\"\{picture_emu(rect.width)}\" cy=\"\{picture_emu(rect.height)}\"/></odXdr:xfrm>"
}

///|
pub fn Session::insert_chart(
  self : Session,
  revision : Int,
  sheet : String,
  settings : SheetChartSettings,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let objects = self.sheet_objects(current, dimensions)
  guard objects.length() < 256 else {
    @failure.reject("limit-exceeded", "Worksheet drawings exceed 256 entries")
  }
  let range = if self.selection.0 == sheet {
    self.selection.1
  } else {
    Range::parse("A1")
  }
  let rect : @layout.Border = {
    x: dimensions.columns.position(range.left),
    y: dimensions.rows.position(range.top),
    width,
    height,
  }
  check_picture_rect("move", rect, dimensions)
  let chart = self.chart_from_settings(sheet, settings)
  ignore(chart.data.paint(width, height, probe, profile))
  let id = for i in 1..<=16384 {
    if !objects.any(object => object.id == i.to_string()) {
      break i.to_string()
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Worksheet drawing identities exhausted")
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let (drawing, sheet_document) = match self.picture_drawing(current) {
    Some((part, _)) => (part, current.document)
    None => {
      let (part, relation) = self.create_sheet_resource(
        sheet,
        "drawing",
        "<xdr:wsDr xmlns:xdr=\"\{picture_uri}\"/>",
        parts,
        created,
        edits,
      )
      let (document, edit) = insert_sheet_drawing(
        current.document,
        relation,
        name="drawing",
      )
      edits.push((sheet, edit))
      (part, document)
    }
  }
  let (_, relation) = self.create_sheet_resource(
    drawing,
    "chart",
    chart.markup(),
    parts,
    created,
    edits,
  )
  let source = "<odXdr:graphicFrame xmlns:odXdr=\"\{picture_uri}\" xmlns:odA=\"\{picture_drawing_uri}\" xmlns:c=\"\{chart_uri}\" xmlns:r=\"\{relationship_uri[:relationship_uri.length()-1]}\"><odXdr:nvGraphicFramePr><odXdr:cNvPr id=\"\{id}\" name=\"Chart\"/><odXdr:cNvGraphicFramePr/></odXdr:nvGraphicFramePr>\{chart_transform(rect)}<odA:graphic><odA:graphicData uri=\"\{chart_uri}\"><c:chart r:id=\"\{relation}\"/></odA:graphicData></odA:graphic></odXdr:graphicFrame>"
  let document = parts.get(drawing).unwrap_or_else(() => self.part_xml(drawing))
  let (document, edit) = document.edit_source([
    insertion(
      document.nodes()[0],
      picture_frame_source("move", rect, source, dimensions),
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
  let candidate = { ..self, sheets, parts, }
  ignore(candidate.sheet_objects(sheets[index], dimensions))
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
    drawing_selection=Some((sheet, id)),
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}

///|
pub fn Session::set_chart(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  settings : SheetChartSettings,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let objects = self.sheet_objects(
    current,
    self.resolved_dimensions(current, probe, profile),
  )
  let object = objects
    .iter()
    .find_first(object => object.id == id && object.chart is Some(_))
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet chart no longer exists")
    })
  object.check_change(false)
  let (part, old) = object.chart.unwrap()
  let next = self.chart_from_settings(sheet, settings)
  if old.markup() == next.markup() {
    return self.query()
  }
  ignore(next.data.paint(object.rect.width, object.rect.height, probe, profile))
  let original = self.part_xml(part)
  guard !original.source().contains("<!--") else {
    @failure.reject(
      "protected-content", "Chart comments require source-preserving editing",
    )
  }
  let (document, edit) = pivot_root_edit(
    original,
    next.markup().split("?>").last().unwrap().to_owned(),
  )
  let parts = self.parts.copy()
  parts[part] = document
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(part, edit)],
    self.selection,
    parts~,
    drawing_selection=self.drawing_selection,
    font_context=Some((probe, profile.copy())),
  )
  self.query()
}
