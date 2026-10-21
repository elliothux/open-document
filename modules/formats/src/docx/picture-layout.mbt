///|
fn Session::check_picture_layout(
  self : Session,
  document : @xml.Document,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Unit raise @failure.Failure {
  guard probe is Some(probe) else { return }
  if [self.document(), document].any(source => {
      source
      .nodes()
      .any(node => {
        node.uri == picture_inline_uri &&
        ["wrapTopAndBottom", "wrapSquare"].contains(node.name)
      })
    }) {
    let after = self.flow_from(document)
    let result = @layout.paginate(
      probe,
      after,
      profile,
      images.unwrap_or(@layout.Images::new()),
    )
    guard result.diagnostics.is_empty() else {
      @failure.reject(
        "unsupported-layout", "Picture wrapping requires supported document layout",
      )
    }
  }
}
