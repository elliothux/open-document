///|
fn read_chart(
  opc : @opc.Package,
  source : Ref,
  parts : Map[String, @xml.Document],
  theme : Theme,
) -> @chart.Resource raise @failure.Failure {
  let frame = source.child("graphic").bind(g => g.child("graphicData")).unwrap()
  let link = frame.child("chart", uri=chart_uri).unwrap().node
    .attribute("id", uri=relationship_uri)
    .unwrap_or("")
  let part = @chart.link(opc, source.tree.part, link, "chart", parts)
  @chart.read(opc, part, parts) catch {
    @failure.Failure(code="unsupported-chart", ..) => {
      let document = parts.get(part).unwrap_or_else(() => opc.xml(part))
      let tree = Tree::new(part, document)
      let root = tree.root("chartSpace", uri=chart_uri)
      let mapping = theme.mapping.copy()
      if tree.one(root.id, "clrMapOvr", uri=chart_uri) is Some(node) {
        guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
          node.attributes.all(a => {
            a.uri.is_empty() &&
            [
              "bg1", "tx1", "bg2", "tx2", "accent1", "accent2", "accent3", "accent4",
              "accent5", "accent6", "hlink", "folHlink",
            ].contains(a.name) &&
            theme.colors.contains(a.value)
          }) else {
          @failure.reject(
            "unsupported-chart", "Unsupported native chart color mapping",
          )
        }
        for attr in node.attributes {
          mapping[attr.name] = attr.value
        }
      }
      let theme = { ..theme, mapping, }
      @chart.read_native_pie(opc, part, parts, id => {
        color_rgba(theme, { tree, node: tree.nodes[id], })
      })
    }
    error => raise error
  }
}
