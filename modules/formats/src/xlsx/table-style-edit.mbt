///|
pub(all) struct TableStyleSettings {
  name : String?
  first_column : Bool
  last_column : Bool
  row_stripes : Bool
  column_stripes : Bool
}

///|
fn table_style_index(name : String?) -> Int32? {
  match name {
    Some("TableStyleMedium1") => Some(0)
    Some("TableStyleMedium2") => Some(1)
    Some("TableStyleMedium3") => Some(2)
    Some("TableStyleMedium4") => Some(3)
    Some("TableStyleMedium5") => Some(4)
    Some("TableStyleMedium6") => Some(5)
    Some("TableStyleMedium7") => Some(6)
    Some("TableStyleMedium8") => Some(7)
    Some("TableStyleMedium9") => Some(8)
    Some("TableStyleMedium10") => Some(9)
    Some("TableStyleMedium11") => Some(10)
    Some("TableStyleMedium12") => Some(11)
    Some("TableStyleMedium13") => Some(12)
    Some("TableStyleMedium14") => Some(13)
    Some("TableStyleMedium15") => Some(14)
    Some("TableStyleMedium16") => Some(15)
    Some("TableStyleMedium17") => Some(16)
    Some("TableStyleMedium18") => Some(17)
    Some("TableStyleMedium19") => Some(18)
    Some("TableStyleMedium20") => Some(19)
    Some("TableStyleMedium21") => Some(20)
    Some("TableStyleMedium22") => Some(21)
    Some("TableStyleMedium23") => Some(22)
    Some("TableStyleMedium24") => Some(23)
    Some("TableStyleMedium25") => Some(24)
    Some("TableStyleMedium26") => Some(25)
    Some("TableStyleMedium27") => Some(26)
    Some("TableStyleMedium28") => Some(27)
    Some("TableStyleLight1") => Some(28)
    Some("TableStyleLight2") => Some(29)
    Some("TableStyleLight3") => Some(30)
    Some("TableStyleLight4") => Some(31)
    Some("TableStyleLight5") => Some(32)
    Some("TableStyleLight6") => Some(33)
    Some("TableStyleLight7") => Some(34)
    Some("TableStyleLight8") => Some(35)
    Some("TableStyleLight9") => Some(36)
    Some("TableStyleLight10") => Some(37)
    Some("TableStyleLight11") => Some(38)
    Some("TableStyleLight12") => Some(39)
    Some("TableStyleLight13") => Some(40)
    Some("TableStyleLight14") => Some(41)
    Some("TableStyleLight15") => Some(42)
    Some("TableStyleLight16") => Some(43)
    Some("TableStyleLight17") => Some(44)
    Some("TableStyleLight18") => Some(45)
    Some("TableStyleLight19") => Some(46)
    Some("TableStyleLight20") => Some(47)
    Some("TableStyleLight21") => Some(48)
    Some("TableStyleDark1") => Some(49)
    Some("TableStyleDark2") => Some(50)
    Some("TableStyleDark3") => Some(51)
    Some("TableStyleDark4") => Some(52)
    Some("TableStyleDark5") => Some(53)
    Some("TableStyleDark6") => Some(54)
    Some("TableStyleDark7") => Some(55)
    Some("TableStyleDark8") => Some(56)
    Some("TableStyleDark9") => Some(57)
    Some("TableStyleDark10") => Some(58)
    Some("TableStyleDark11") => Some(59)
    _ => None
  }
}

///|
fn Session::set_table_style(
  self : Session,
  sheet : String,
  id : Int32,
  settings : TableStyleSettings,
) -> Json raise @failure.Failure {
  let custom = self.custom_table_styles(self.parts)
  if settings.name is Some(name) {
    if custom.get(name.to_upper()) is Some(style) {
      guard style.reason.is_empty() else {
        @failure.reject("protected-content", style.reason)
      }
    } else {
      guard table_style_index(Some(name)) is Some(_) else {
        @failure.reject("invalid-operation", "Unknown table style")
      }
    }
  }
  let settings = {
    ..settings,
    name: settings.name.map(name => {
      custom.get(name.to_upper()).map(style => style.name).unwrap_or(name)
    }),
  }
  let table = self.table_for_edit(sheet, id)
  let document = self.part_xml(table.part)
  let tree = table_edit_tree(table, document)
  if table.style == settings.name &&
    table.first_column == settings.first_column &&
    table.last_column == settings.last_column &&
    table.row_stripes == settings.row_stripes &&
    table.column_stripes == settings.column_stripes {
    return self.query()
  }
  let attributes = [
    ("name", settings.name.unwrap_or("")),
    ("showFirstColumn", if settings.first_column { "1" } else { "0" }),
    ("showLastColumn", if settings.last_column { "1" } else { "0" }),
    ("showRowStripes", if settings.row_stripes { "1" } else { "0" }),
    ("showColumnStripes", if settings.column_stripes { "1" } else { "0" }),
  ]
  let root = tree.root("table")
  let changes = if tree.one(root.id, "tableStyleInfo") is Some(style) {
    metadata_changes(style, attributes)
  } else {
    let values = attributes
      .map(pair => " \{pair.0}=\"\{escaped_attribute(pair.1)}\"")
      .join("")
    [
      insertion(
        root,
        "<od:tableStyleInfo xmlns:od=\"\{spreadsheet_uri}\"\{values}/>",
      ),
    ]
  }
  let (document, edit) = document.edit_source(changes)
  let parts = self.parts.copy()
  parts[table.part] = document
  let sheets = self.sheets.copy()
  let calculation = self.calculate(
    sheets,
    self.calculation,
    [],
    self.workbook,
    parts~,
  )
  self.commit(
    sheets,
    self.workbook,
    calculation,
    [(table.part, edit)],
    self.selection,
    parts~,
  )
  self.query()
}
