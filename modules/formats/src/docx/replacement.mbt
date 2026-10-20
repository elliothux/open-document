///|
fn WordTree::split_input(
  self : WordTree,
  document : @xml.Document,
  paragraph : Int,
  insertion : Int?,
  offset : Int,
  parts : Array[String],
  tail : String,
  merge~ : Bool,
  source_limit~ : Int,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if insertion is Some(id) && self.nodes[id].name == "fldSimple" {
    return self.split_field_input(
      document, paragraph, id, offset, parts, tail, source_limit,
    )
  }
  if insertion is Some(id) && self.nodes[id].name == "drawing" {
    return self.split_picture_input(
      document, paragraph, id, offset, parts, tail, source_limit,
    )
  }
  if insertion is Some(id) && self.nodes[id].name != "t" {
    return self.split_control_input(
      document, paragraph, id, offset, parts, tail, source_limit,
    )
  }
  let p = self.nodes[paragraph]
  let parent = self.nodes[p.parent]
  let source = document.source()
  let next = structure_opening(p) +
    self.continuation_properties(document, paragraph)
  let run = match insertion {
    Some(id) => Some(self.nodes[self.nodes[id].parent])
    None => self.child(paragraph, "r").map(id => self.nodes[id])
  }
  let prefix = p.qualified[:p.qualified.length() - 1].to_owned()
  let run_name = run.map(run => run.qualified).unwrap_or(prefix + "r")
  let run_opening = run
    .map(run => structure_opening(run))
    .unwrap_or("<\{run_name}>")
  let properties = match run {
    Some(run) =>
      self
      .child(run.id, "rPr")
      .map(id => {
        let node = self.nodes[id]
        source[node.start:node.end].to_owned()
      })
      .unwrap_or("")
    None => self.empty_run_properties(document, paragraph)
  }
  let output = StringBuilder()
  let changes : Array[@xml.SourceChange] = []
  if insertion is Some(id) {
    let node = self.nodes[id]
    guard node.attributes
      .iter()
      .all(attribute => {
        attribute.uri == "http://www.w3.org/XML/1998/namespace" &&
        attribute.name == "space"
      }) &&
      !source[node.opening_end:node.closing_start].contains("<!--") &&
      !source[node.opening_end:node.closing_start].contains("<?") else {
      @failure.reject(
        "protected-content", "Unknown text markup prevents splitting",
      )
    }
    let opening = structure_opening(node)
    let opening = opening[:opening.length() - 1].to_owned() +
      " xml:space=\"preserve\">"
    let (link_opening, link_closing) = run
      .map(run => self.hyperlink_frame(document, run.id))
      .unwrap_or(("", ""))
    let frame = "</\{node.qualified}></\{run_name}>\{link_closing}</\{p.qualified}>\{next}\{link_opening}\{run_opening}\{properties}\{opening}"
    let frames = frame.length().to_int64() * (parts.length() - 1).to_int64()
    let minimum = frames +
      offset.to_int64() +
      tail.length().to_int64() +
      parts.iter().fold(init=0L, (sum, part) => sum + part.length().to_int64())
    guard minimum <= source_limit.to_int64() else {
      @failure.reject(
        "limit-exceeded", "Multiline source fragment budget exceeded",
      )
    }
    let values = parts.map(value => {
      inline_content(value, opening, "</\{node.qualified}>", source_limit)
    })
    let left = inline_content(
      node.text[:offset].to_owned(),
      opening,
      "</\{node.qualified}>",
      source_limit,
    )
    let tail = inline_content(
      tail,
      opening,
      "</\{node.qualified}>",
      source_limit,
    )
    let ending = if node.empty { "</\{node.qualified}>" } else { "" }
    let units = frames +
      left.length().to_int64() +
      tail.length().to_int64() +
      ending.length().to_int64() +
      (if node.empty { 1L } else { 0L }) +
      values
      .iter()
      .fold(init=0L, (sum, value) => sum + value.length().to_int64())
    guard units <= source_limit.to_int64() else {
      @failure.reject(
        "limit-exceeded", "Multiline source fragment budget exceeded",
      )
    }
    output.write_string(left + values[0])
    for index in 1..<parts.length() {
      output.write_string(frame)
      output.write_string(values[index])
    }
    output.write_string(tail + ending)
    let space = node.attributes
      .iter()
      .find_first(attribute => attribute.name == "space")
    changes.push(
      if space is Some(attribute) {
        {
          node: node.id,
          offset: attribute.start - node.start,
          length: attribute.end - attribute.start,
          xml: "preserve",
        }
      } else {
        {
          node: node.id,
          offset: node.opening_end -
          node.start -
          (if node.empty { 2 } else { 1 }),
          length: 0,
          xml: " xml:space=\"preserve\"",
        }
      },
    )
    changes.push({
      node: parent.id,
      offset: (if node.empty { node.opening_end - 2 } else { node.opening_end }) -
      parent.start,
      length: if node.empty {
        2
      } else {
        node.closing_start - node.opening_end
      },
      xml: (if node.empty { ">" } else { "" }) + output.to_string(),
    })
  } else {
    let name = run_name[:run_name.length() - 1].to_owned() + "t"
    let opening = "\{run_opening}\{properties}<\{name} xml:space=\"preserve\">"
    let closing = "</\{name}></\{run_name}>"
    let frame_units = (
        opening.length().to_int64() + closing.length().to_int64()
      ) *
      parts.length().to_int64() +
      (p.qualified.length().to_int64() + 3 + next.length().to_int64()) *
      (parts.length() - 1).to_int64()
    guard frame_units <= source_limit.to_int64() else {
      @failure.reject(
        "limit-exceeded", "Multiline source fragment budget exceeded",
      )
    }
    let text_opening = "<\{name} xml:space=\"preserve\">"
    let values = parts.map(value => {
      inline_content(value, text_opening, "</\{name}>", source_limit)
    })
    let ending = if p.empty && !merge { "</\{p.qualified}>" } else { "" }
    let units = frame_units +
      ending.length().to_int64() +
      (if p.empty { 1L } else { 0L }) +
      values
      .iter()
      .fold(init=0L, (sum, value) => sum + value.length().to_int64())
    guard units <= source_limit.to_int64() else {
      @failure.reject(
        "limit-exceeded", "Multiline source fragment budget exceeded",
      )
    }
    for index in 0..<parts.length() {
      if index > 0 {
        output.write_string("</\{p.qualified}>\{next}")
      }
      output.write_string(opening + values[index] + closing)
    }
    changes.push({
      node: parent.id,
      offset: (if p.empty { p.opening_end - 2 } else { p.closing_start }) -
      parent.start,
      length: if p.empty {
        2
      } else {
        0
      },
      xml: (if p.empty { ">" } else { "" }) + output.to_string() + ending,
    })
  }
  changes
}
