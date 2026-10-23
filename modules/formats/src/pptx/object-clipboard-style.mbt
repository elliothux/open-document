///|
fn clipboard_source_change(source : Ref, markup : String) -> @xml.SourceChange {
  let parent = source.tree.nodes[source.node.parent]
  {
    node: parent.id,
    offset: source.node.start - parent.start,
    length: source.node.end - source.node.start,
    xml: markup,
  }
}

///|
fn check_clipboard_object(object : Object) -> Unit raise @failure.Failure {
  guard ["shape", "image", "group", "table", "chart"].contains(object.kind) &&
    object.geometry is Some(_) &&
    ["", "Group members are read-only"].contains(object.read_only) &&
    object.diagnostic.is_empty() &&
    (object.paragraphs.is_empty() || object.text_reason.is_empty()) &&
    object.media
    .map(media => media.reason.is_empty() && object.image is Some(_))
    .unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Object clipboard requires supported local shapes pictures tables charts media or groups",
    )
  }
  let paragraphs = object.table
    .map(table => {
      table.rows
      .map(row => row.cells.map(cell => cell.paragraphs).flatten())
      .flatten()
    })
    .unwrap_or(object.paragraphs)
  for paragraph in paragraphs {
    guard paragraph.runs.all(run => {
      run.math is None &&
      run.date_field is None &&
      run.source.map(s => ["r", "br"].contains(s.node.name)).unwrap_or(true)
    }) else {
      @failure.reject(
        "protected-content", "Object fields and equations require portable object support",
      )
    }
  }
}

///|
fn clipboard_line_markup(object : Object) -> String {
  let join = if object.join == "miter" {
    "<a:miter lim='\{(object.miter*100000).round().to_int64()}'/>"
  } else {
    "<a:\{object.join}/>"
  }
  let ends = [("headEnd", object.ends.0), ("tailEnd", object.ends.1)]
    .map(pair => {
      let (name, end) = pair
      "<a:\{name} type='\{end.kind}' w='\{end.width}' len='\{end.length}'/>"
    })
    .join("")
  let paint = paint_markup(
    if object.stroke.is_empty() {
      None
    } else {
      Some(object.stroke)
    },
    opacity=object.stroke_alpha,
  )
  "<a:ln xmlns:a='\{drawing_uri}' w='\{(object.line_width*12700).round().to_int64()}' cap='\{object.cap}'>\{paint}<a:prstDash val='\{object.dash}'/>\{join}\{ends}</a:ln>"
}

///|
fn clipboard_object_style(
  object : Object,
  image_link : String?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes = []
  if object.kind == "group" {
    return changes
  }
  let source = object.source
  if source.child("style", uri=presentation_uri) is Some(style) {
    changes.push(clipboard_source_change(style, ""))
  }
  let props = source.child("spPr", uri=presentation_uri).unwrap()
  let fill = if object.kind == "image" {
    None
  } else if image_link is Some(id) {
    Some(
      image_fill_markup(
        id,
        object.opacity,
        object.crop,
        object.tile,
        insets=object.insets,
      ),
    )
  } else if object.gradient is Some((stops, angle, scaled)) {
    Some(BackgroundFill::Linear(stops, angle, scaled).markup())
  } else {
    Some(
      paint_markup(
        if object.fill.is_empty() {
          None
        } else {
          Some(object.fill)
        },
        opacity=object.fill_alpha,
      ),
    )
  }
  if fill is Some(markup) {
    let previous = paint_fill(props)
    if previous is Some(node) {
      guard !source_xml({ tree: props.tree, node, }).contains("<!--") else {
        @failure.reject(
          "protected-content", "Annotated object paints require portable copying support",
        )
      }
    }
    changes.push(
      paint_child_change(props, previous, markup, [
        "ln", "effectLst", "effectDag", "scene3d", "sp3d", "extLst",
      ]),
    )
    if flag(source.node, "useBgFill") {
      changes.push(attribute_change(source, "useBgFill", "0"))
    }
  }
  let line = props.child("ln")
  guard line
    .map(p => !source_xml(p).contains("<!--") && !source_xml(p).contains("<?"))
    .unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Annotated borders require portable copying support",
    )
  }
  changes.push(
    paint_child_change(
      props,
      line.map(p => p.node),
      clipboard_line_markup(object),
      ["effectLst", "effectDag", "scene3d", "sp3d", "extLst"],
    ),
  )
  if object.kind == "image" && image_link is Some(id) {
    let picture = source.child("blipFill", uri=presentation_uri).unwrap()
    guard !source_xml(picture).contains("<!--") &&
      !source_xml(picture).contains("<?") else {
      @failure.reject(
        "protected-content", "Annotated image bindings require portable copying support",
      )
    }
    let markup = image_fill_markup(
        id,
        object.opacity,
        object.crop,
        object.tile,
        insets=object.insets,
      )
      .replace(
        old="<a:blipFill",
        new="<p:blipFill xmlns:p='\{presentation_uri}'",
      )
      .replace(old="</a:blipFill>", new="</p:blipFill>")
    changes.push(clipboard_source_change(picture, markup))
  }
  if placeholder_node(source) is Some(ph) {
    changes.push(clipboard_source_change(ph, ""))
  }
  changes.append(
    clipboard_body_style(
      source,
      object.body,
      object.paragraphs,
      presentation_uri,
    ),
  )
  changes
}

///|
fn clipboard_body_style(
  source : Ref,
  settings : Body,
  paragraphs : Array[TextParagraph],
  uri : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes = []
  if source.child("txBody", uri~) is Some(body) {
    let attrs : Map[String, String] = {
      "lIns": (settings.left * 12700).round().to_int64().to_string(),
      "rIns": (settings.right * 12700).round().to_int64().to_string(),
      "tIns": (settings.top * 12700).round().to_int64().to_string(),
      "bIns": (settings.bottom * 12700).round().to_int64().to_string(),
      "anchor": settings.anchor,
      "wrap": if settings.wrap {
        "square"
      } else {
        "none"
      },
    }
    let properties = body.child("bodyPr")
    let markup = if properties is Some(p) {
      frame_opening(p, attrs) +
      (if p.node.empty {
        ""
      } else {
        p.tree.document.source()[p.node.opening_end:p.node.closing_start].to_owned()
      }) +
      "</\{p.node.qualified}>"
    } else {
      "<a:bodyPr xmlns:a='\{drawing_uri}' " +
      attrs.iter().map(pair => pair.0 + "='" + pair.1 + "'").join(" ") +
      "/>"
    }
    changes.push(
      paint_child_change(body, properties.map(p => p.node), markup, [
        "lstStyle", "p",
      ]),
    )
    for paragraph in paragraphs {
      let props = paragraph.source.child("pPr")
      changes.push(
        paint_child_change(
          paragraph.source,
          props.map(p => p.node),
          clipboard_paragraph_properties(paragraph, properties=props),
          ["r", "br", "endParaRPr"],
        ),
      )
      for run in paragraph.runs {
        if run.source is Some(r) {
          let markup = if r.node.name == "br" {
            "<a:br xmlns:a='\{drawing_uri}'>" +
            formatted_properties(
              r.child("rPr"),
              "rPr",
              Some(clipboard_run_style(run.style())),
            ) +
            "</a:br>"
          } else {
            let output = StringBuilder()
            let mut offset = 0
            for (style, text) in run.parts {
              output.write_string(
                format_run(
                  run,
                  offset,
                  offset + text.length(),
                  Some(clipboard_run_style(style)),
                ),
              )
              offset += text.length()
            }
            output.to_string()
          }
          changes.push(clipboard_source_change(r, markup))
        }
      }
      let ending = paragraph.source.child("endParaRPr")
      changes.push(
        paint_child_change(
          paragraph.source,
          ending.map(p => p.node),
          formatted_properties(
            ending,
            "endParaRPr",
            Some(clipboard_run_style(paragraph.runs.last().unwrap().style())),
          ),
          [],
        ),
      )
    }
  }
  changes
}
