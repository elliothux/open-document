///|
fn Session::default_row_height(
  self : Session,
  sheet : Sheet,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Double raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let format = tree.one(tree.sheet_root().id, "sheetFormatPr")
  if sheet.dimensions.rows.default_size == 0 ||
    format.map(node => flag(node, "customHeight")).unwrap_or(false) {
    return sheet.dimensions.rows.default_size
  }
  self.normal_row_height(probe, profile).min(409.5)
}

///|
fn Session::normal_row_height(
  self : Session,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Double raise @failure.Failure {
  guard @layout.font_profile_identity(profile, self.normal_font)
    is Some(identity) else {
    @failure.reject(
      "missing-font",
      "Missing font profile mapping: " + self.normal_font,
    )
  }
  let (ascent, descent) = probe.cell_metrics(
    probe.font_index(identity),
    self.normal_size,
  )
  ascent + descent
}
