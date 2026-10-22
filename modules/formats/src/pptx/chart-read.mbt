///|
fn read_chart(
  opc : @opc.Package,
  source : Ref,
  parts : Map[String, @xml.Document],
) -> @chart.Resource raise @failure.Failure {
  let frame = source.child("graphic").bind(g => g.child("graphicData")).unwrap()
  let link = frame.child("chart", uri=chart_uri).unwrap().node
    .attribute("id", uri=relationship_uri)
    .unwrap_or("")
  let part = @chart.link(opc, source.tree.part, link, "chart", parts)
  @chart.read(opc, part, parts)
}
