///|
fn WordTree::row_grid_after(
  self : WordTree,
  row : Int,
) -> Int raise @failure.Failure {
  guard self.child(row, "trPr") is Some(props) &&
    self.child(props, "gridAfter") is Some(id) else {
    return 0
  }
  let node = self.nodes[id]
  let value = @string.parse_int(
    node.attribute("val", uri=word_uri).unwrap_or(""),
  ) catch {
    _ => @failure.reject("invalid-table", "Invalid trailing table grid")
  }
  guard self.table_children(props, "gridAfter").length() == 1 &&
    node.attributes.all(a => a.uri == word_uri && a.name == "val") &&
    self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    value >= 0 &&
    value <= 63 else {
    @failure.reject("invalid-table", "Invalid trailing table grid")
  }
  value
}

///|
fn WordTree::table_row_height(
  self : WordTree,
  row : Int,
) -> (Double, Bool) raise @failure.Failure {
  guard self.child(row, "trPr") is Some(props) &&
    self.child(props, "trHeight") is Some(id) else {
    return (0, false)
  }
  let node = self.nodes[id]
  guard self.table_children(props, "trHeight").length() == 1 &&
    self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri && ["val", "hRule"].contains(a.name)
    }) else {
    @failure.reject(
      "unsupported-layout", "Unknown or duplicate table row height",
    )
  }
  let rule = node.attribute("hRule", uri=word_uri).unwrap_or("atLeast")
  guard ["auto", "atLeast", "exact"].contains(rule) else {
    @failure.reject("unsupported-layout", "Unknown table row height rule")
  }
  let value = self.number(props, "trHeight", "val").unwrap_or(0)
  guard value >= 0 && value <= 288000 && value == value.floor() else {
    @failure.reject(
      "invalid-table", "Row height requires finite nonnegative integer twips",
    )
  }
  (if rule == "auto" { 0.0 } else { value / 20 }, rule == "exact")
}
