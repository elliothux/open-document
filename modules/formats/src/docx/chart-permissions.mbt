///|
priv enum ChartOperation {
  ChartContent
  ChartCopy
  ChartDelete
  ChartRetain
  ChartResize
  ChartPosition
} derive(Eq)

///|
fn WordTree::check_chart_operation(
  self : WordTree,
  id : Int32,
  operation : ChartOperation,
) -> Unit raise @failure.Failure {
  for child in self.descendants(id) {
    let node = self.nodes[child]
    if !node.name.has_suffix("Locks") {
      continue
    }
    guard node.uri == picture_drawing_uri &&
      node.name == "graphicFrameLocks" &&
      self.children[child].is_empty() &&
      node.attributes.all(attribute => {
        attribute.uri.is_empty() &&
        [
          "noGrp", "noSelect", "noResize", "noMove", "noChangeAspect", "noTextEdit",
          "noDelete", "noDrilldown", "noCopy", "noChangeWrap",
        ].contains(attribute.name) &&
        ["0", "1", "false", "true"].contains(attribute.value)
      }) else {
      @failure.reject("protected-content", "Unsupported chart frame locks")
    }
    let blocked = match operation {
      ChartContent => ["noSelect", "noTextEdit"]
      ChartCopy => ["noCopy"]
      ChartDelete => ["noSelect", "noDelete"]
      ChartResize => ["noResize"]
      ChartPosition => ["noMove", "noChangeWrap"]
      ChartRetain => []
    }
    guard !node.attributes.any(attribute => {
      ["1", "true"].contains(attribute.value) &&
      blocked.contains(attribute.name)
    }) else {
      @failure.reject("protected-content", "Chart operation is locked")
    }
  }
}
