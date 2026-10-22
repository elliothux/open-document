///|
fn read_slide(
  opc : @opc.Package,
  main : Tree,
  cache : Map[String, Tree],
  tree : Tree,
  index~ : Int,
  parts~ : Map[String, @xml.Document] = Map([]),
  date_time~ : DateTime? = None,
) -> Slide raise @failure.Failure {
  let page_number = presentation_number(main, index)
  let root = tree.document.nodes()[0]
  guard root.uri == presentation_uri &&
    ["sld", "sldLayout", "sldMaster"].contains(root.name) else {
    @failure.reject("malformed-pptx", "Unknown presentation source root")
  }
  let layout = if root.name == "sld" {
    let layout_part = slide_layout(opc, tree.part, parts).unwrap_or_error(
      @failure.Failure(
        code="malformed-pptx",
        part=tree.part,
        offset=-1,
        message="Missing slide layout",
      ),
    )
    let layout = load_tree(opc, cache, layout_part, parts~)
    ignore(layout.root("sldLayout"))
    Some(layout)
  } else {
    None
  }
  let parent = layout.unwrap_or(tree)
  let master = if root.name == "sldMaster" {
    tree
  } else {
    let master_part = relation(opc, parent.part, "slideMaster", parts~).unwrap_or_error(
      @failure.Failure(
        code="malformed-pptx",
        part=parent.part,
        offset=-1,
        message="Missing slide master",
      ),
    )
    let master = load_tree(opc, cache, master_part, parts~)
    ignore(master.root("sldMaster"))
    master
  }
  let theme_part = relation(opc, master.part, "theme", parts~).unwrap_or_error(
    @failure.Failure(
      code="malformed-pptx",
      part=master.part,
      offset=-1,
      message="Missing master theme",
    ),
  )
  guard master.part != theme_part &&
    tree.part != theme_part &&
    (root.name == "sldMaster" || tree.part != master.part) &&
    layout
    .map(item => {
      item.part != tree.part &&
      item.part != master.part &&
      item.part != theme_part
    })
    .unwrap_or(true) else {
    @failure.reject("malformed-pptx", "Cyclic slide inheritance")
  }
  let layers = [tree]
  if layout is Some(layout) {
    layers.push(layout)
  }
  if master.part != tree.part {
    layers.push(master)
  }
  let theme = {
    ..read_theme(load_tree(opc, cache, theme_part, parts~), layers),
    tables: Some(
      read_table_styles(opc, main, cache, parts) catch {
        @failure.Failure(code="unsupported-table", message~, ..) =>
          { part: None, default_id: "", styles: Map([]), reason: message, }
        error => raise error
      },
    ),
  }
  let defaults = main
    .one(main.document.nodes()[0].id, "defaultTextStyle", uri=presentation_uri)
    .map(node => { tree: main, node, })
  let objects : Array[Object] = []
  let diagnostics : Array[String] = []
  let ids : Map[String, Bool] = Map([])
  let identity = @layout.Matrix::identity()
  if master.part != tree.part &&
    flag(root, "showMasterSp", default=true) &&
    layout
    .map(item => flag(item.document.nodes()[0], "showMasterSp", default=true))
    .unwrap_or(true) {
    read_objects(
      opc,
      master,
      shape_tree(master).id,
      theme,
      None,
      master,
      defaults,
      identity,
      "Master objects are read-only",
      0,
      objects,
      ids,
      parts,
      page_number,
      date_time,
    )
  }
  if layout is Some(layout) && flag(root, "showMasterSp", default=true) {
    read_objects(
      opc,
      layout,
      shape_tree(layout).id,
      theme,
      None,
      master,
      defaults,
      identity,
      "Layout objects are read-only",
      0,
      objects,
      ids,
      parts,
      page_number,
      date_time,
    )
  }
  read_objects(
    opc,
    tree,
    shape_tree(tree).id,
    theme,
    layout,
    master,
    defaults,
    identity,
    "",
    0,
    objects,
    ids,
    parts,
    page_number,
    date_time,
  )
  let mut background = Solid("ffffff")
  for layer in layers {
    let container = layer.required(
      layer.document.nodes()[0].id,
      "cSld",
      uri=presentation_uri,
    )
    if layer.one(container.id, "bg", uri=presentation_uri) is Some(bg) {
      if layer.one(bg.id, "bgPr", uri=presentation_uri) is Some(properties) {
        background = read_background_fill(
          theme,
          { tree: layer, node: properties, },
          opc~,
          parts~,
        ) catch {
          @failure.Failure(code="unsupported-style", message~, ..) => {
            diagnostics.push(layer.part + ":" + message)
            Solid("ffffff")
          }
          error => raise error
        }
      } else if layer.one(bg.id, "bgRef", uri=presentation_uri)
        is Some(reference) {
        background = (fn() raise @failure.Failure {
          let resolved = theme_reference(
            theme,
            { tree: layer, node: reference, },
            "fill",
          )
          guard resolved is Some((item, ph)) else {
            @failure.reject("unsupported-style", "Unsupported theme background")
          }
          read_background_fill(theme, item, opc~, parts~, placeholder=Some(ph))
        })() catch {
          @failure.Failure(code="unsupported-style", message~, ..) => {
            diagnostics.push(layer.part + ":" + message)
            Solid("ffffff")
          }
          error => raise error
        }
      } else {
        diagnostics.push(layer.part + ":Unsupported background reference")
      }
      break
    }
  }
  let mut read_only = ""
  for index, object in objects {
    if object.source.node.name == "cxnSp" &&
      ["", "Group members are read-only"].contains(object.read_only) {
      let problem = connector_problem(object, objects)
      if !problem.is_empty() {
        objects[index] = {
          ..object,
          read_only: problem,
          diagnostic: problem,
          text_reason: problem,
        }
      }
    }
  }
  for index, object in objects {
    if object.kind == "group" {
      let issue = objects
        .iter()
        .find_first(child => {
          child.source.tree.part == object.source.tree.part &&
          child.source.node.start > object.source.node.start &&
          child.source.node.end < object.source.node.end &&
          !child.diagnostic.is_empty()
        })
      if issue is Some(issue) {
        objects[index] = { ..object, read_only: issue.diagnostic, }
      }
    }
  }
  for object in objects {
    if !object.diagnostic.is_empty() {
      diagnostics.push(object.id + ":" + object.diagnostic)
    }
    if object.paragraphs.any(p => {
        p.runs.any(run => run.has_date_source() && run.date_field is None)
      }) {
      diagnostics.push(
        object.id +
        ":Date fields require a supported format, language and explicit time",
      )
    } else if object.kind != "group" &&
      object.kind != "chart" &&
      object.source.node.name != "cxnSp" &&
      !object.text_reason.is_empty() &&
      !calculated_field_reason(object.text_reason) &&
      object.text_reason != math_text_reason &&
      object.read_only.is_empty() {
      diagnostics.push(object.id + ":" + object.text_reason)
    }
    if object.geometry is None {
      read_only = "Unresolved object bounds prevent direct canvas editing"
    }
  }
  {
    tree,
    date_time: date_time.map(time => time.value),
    hidden: !flag(root, "show", default=true),
    objects,
    background,
    diagnostics,
    read_only,
  }
}
