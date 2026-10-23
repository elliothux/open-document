///|
fn fragment_run_markup(
  tree : WordTree,
  document : @xml.Document,
  paragraph : Int,
  run : Int?,
  style : RunStyle,
  themes : Map[String, String],
  pictures : Map[Int, String],
  limit : Int,
  start~ : Int = 0,
  end~ : Int = 2147483647,
) -> String raise @failure.Failure {
  let chunks : Array[(String, Int?)] = []
  let mut pending = StringBuilder()
  if run is Some(run) {
    for child in tree.children[run] {
      let node = tree.nodes[child]
      if node.name == "drawing" || pictures.contains(child) {
        chunks.push((pending.to_string(), None))
        pending = StringBuilder()
        chunks.push(("", Some(child)))
      } else if node.name != "rPr" {
        pending.write_string(inline_text(node))
      }
    }
  }
  chunks.push((pending.to_string(), None))
  let output = StringBuilder()
  let mut units = 0
  let mut cursor = 0
  for (text, drawing) in chunks {
    let count = if drawing is Some(_) { 1 } else { text.length() }
    let left = (start - cursor).clamp(min=0, max=count)
    let right = (end - cursor).clamp(min=0, max=count)
    cursor += count
    if count > 0 && left == right {
      continue
    }
    let text = if drawing is Some(_) {
      text
    } else {
      text[left:right].to_owned()
    }
    let pieces = style.font_runs(
      if drawing is Some(_) {
        "\ufffc"
      } else {
        text.replace_all(old="\n", new="\u2028")
      },
      themes,
    )
    for (style, text) in pieces {
      let format = style.fragment_format()
      format.validate()
      let properties = formatted_properties(
        tree,
        document,
        run.unwrap_or(paragraph),
        "rPr",
        format.properties(),
      )
      let content = if drawing is Some(id) {
        pictures[id]
      } else {
        inline_markup(text, limit)
      }
      let xml = "<od:r>" + properties + content + "</od:r>"
      guard xml.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich picture run exceeds clipboard budget",
        )
      }
      units += xml.length()
      output.write_string(xml)
    }
  }
  output.to_string()
}
