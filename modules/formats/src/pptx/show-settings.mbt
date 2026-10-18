///|
pub(all) enum ShowRange {
  ShowAll
  ShowRange(Int, Int)
  ShowCustom(String)
} derive(Eq)

///|
pub extend ShowRange with Eq::{equal, not_equal}

///|
pub(all) struct ShowSettings {
  slides : ShowRange
  timings : Bool
  animations : Bool
  cycling : Bool
} derive(Eq)

///|
pub extend ShowSettings with Eq::{equal, not_equal}

///|
pub fn ShowSettings::default() -> ShowSettings {
  { slides: ShowAll, timings: true, animations: true, cycling: false, }
}

///|
fn ShowSettings::json(self : ShowSettings) -> Json {
  let slides : Json = match self.slides {
    ShowAll => { "kind": "all" }
    ShowRange(first, last) => { "kind": "range", "first": first, "last": last }
    ShowCustom(id) => { "kind": "custom", "id": id }
  }
  {
    "slides": slides,
    "timings": self.timings,
    "animations": self.animations,
    "loop": self.cycling,
  }
}

///|
fn Session::show_properties(
  self : Session,
  parts~ : Map[String, @xml.Document] = self.parts,
) -> Tree? raise @failure.Failure {
  let links = self.opc
    .relationships(
      replacements=self.replacements(self.main, self.slides, parts),
      removed=self.removed,
    )
    .filter(link => {
      link.owner == self.main.part &&
      link.kind == relationship_uri + "/presProps"
    })
  guard links.length() <= 1 && links.all(link => !link.external) else {
    @failure.reject(
      "protected-content", "Ambiguous or external presentation properties",
    )
  }
  links
  .get(0)
  .map(link => {
    let tree = load_tree(self.opc, self.cache, link.target, parts~)
    ignore(tree.root("presentationPr"))
    tree
  })
}

///|
fn Session::validate_show_settings(
  self : Session,
  value : ShowSettings,
  count~ : Int = self.slides.length(),
) -> Unit raise @failure.Failure {
  match value.slides {
    ShowAll => ()
    ShowRange(first, last) => {
      guard first >= 1 && first <= last && last <= count else {
        @failure.reject(
          "invalid-operation", "Show range is outside the presentation",
        )
      }
    }
    ShowCustom(id) => {
      guard self.read_custom_shows().any(show => show.id == id) else {
        @failure.reject(
          "invalid-operation", "Selected custom show no longer exists",
        )
      }
    }
  }
}

///|
fn Session::read_show_settings(
  self : Session,
  parts~ : Map[String, @xml.Document] = self.parts,
  count~ : Int = self.slides.length(),
) -> ShowSettings raise @failure.Failure {
  guard self.show_properties(parts~) is Some(tree) &&
    tree.one(tree.root("presentationPr").id, "showPr", uri=presentation_uri)
    is Some(node) else {
    return ShowSettings::default()
  }
  custom_show_node(
    tree,
    node,
    "showPr",
    ["loop", "showAnimation", "showNarration", "useTimings"],
    [
      "present", "browse", "kiosk", "sldAll", "sldRg", "custShow", "penClr", "extLst",
    ],
  )
  let ranges = tree.children
    .get(node.id)
    .unwrap_or([])
    .filter(child => ["sldAll", "sldRg", "custShow"].contains(child.name))
  guard ranges.length() <= 1 else {
    @failure.reject("protected-content", "Ambiguous slide show selection")
  }
  let slides = match ranges.get(0) {
    None => ShowAll
    Some(range) => {
      custom_show_node(
        tree,
        range,
        range.name,
        if range.name == "sldRg" {
          ["st", "end"]
        } else if range.name == "custShow" {
          ["id"]
        } else {
          []
        },
        [],
      )
      let source = tree.document.source()[range.start:range.end]
      guard !source.contains("<!--") && !source.contains("<?") else {
        @failure.reject(
          "protected-content", "Opaque show selection is protected",
        )
      }
      match range.name {
        "sldRg" =>
          ShowRange(
            number(range.attribute("st").unwrap_or(""), 1, 256).to_int(),
            number(range.attribute("end").unwrap_or(""), 1, 256).to_int(),
          )
        "custShow" =>
          ShowCustom(
            number(range.attribute("id").unwrap_or(""), 0, 4294967295)
            .to_int64()
            .to_string(),
          )
        _ => ShowAll
      }
    }
  }
  let value : ShowSettings = {
    slides,
    timings: flag(node, "useTimings", default=true),
    animations: flag(node, "showAnimation", default=true),
    cycling: flag(node, "loop", default=false),
  }
  self.validate_show_settings(value, count~)
  value
}

///|
fn Session::show_settings_query(self : Session) -> Json {
  {
    "value": self.read_show_settings().json(),
    "reason": self.slide_visibility_reason(),
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": Json::null(), "reason": message }
  }
}

///|
fn show_range_markup(value : ShowRange) -> String raise @failure.Failure {
  let attrs = "xmlns:od=\"\{presentation_uri}\""
  match value {
    ShowAll => "<od:sldAll \{attrs}/>"
    ShowRange(first, last) =>
      "<od:sldRg \{attrs} st=\"\{first}\" end=\"\{last}\"/>"
    ShowCustom(id) => "<od:custShow \{attrs} id=\"\{xml_attribute(id)}\"/>"
  }
}

///|
fn show_settings_markup(value : ShowSettings) -> String raise @failure.Failure {
  "<od:showPr xmlns:od=\"\{presentation_uri}\" useTimings=\"\{if value.timings { 1 } else { 0 }}\" showAnimation=\"\{if value.animations { 1 } else { 0 }}\" loop=\"\{if value.cycling { 1 } else { 0 }}\">\{show_range_markup(value.slides)}</od:showPr>"
}

///|
fn Session::set_show_settings(
  self : Session,
  value : ShowSettings,
) -> Json raise @failure.Failure {
  self.validate_show_settings(value)
  let previous = self.read_show_settings()
  if previous == value {
    return self.query()
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  if self.show_properties() is Some(tree) {
    let root = tree.root("presentationPr")
    let changes : Array[@xml.SourceChange] = []
    if tree.one(root.id, "showPr", uri=presentation_uri) is Some(node) {
      for
        (key, old, next) in [
          ("useTimings", previous.timings, value.timings),
          ("showAnimation", previous.animations, value.animations),
          ("loop", previous.cycling, value.cycling),
        ] {
        if old != next {
          changes.push(
            attribute_change({ tree, node, }, key, if next { "1" } else { "0" }),
          )
        }
      }
      if previous.slides != value.slides {
        let range = tree.children
          .get(node.id)
          .unwrap_or([])
          .iter()
          .find_first(child => {
            ["sldAll", "sldRg", "custShow"].contains(child.name)
          })
        let markup = show_range_markup(value.slides)
        if range is Some(range) {
          changes.push({
            node: node.id,
            offset: range.start - node.start,
            length: range.end - range.start,
            xml: markup,
          })
        } else {
          let next = tree.children
            .get(node.id)
            .unwrap_or([])
            .iter()
            .find_first(child => ["penClr", "extLst"].contains(child.name))
          changes.push(
            if next is Some(next) {
              {
                node: node.id,
                offset: next.start - node.start,
                length: 0,
                xml: markup,
              }
            } else {
              insertion(node, markup)
            },
          )
        }
      }
    } else {
      let following = tree.children
        .get(root.id)
        .unwrap_or([])
        .iter()
        .find_first(node => ["clrMru", "extLst"].contains(node.name))
      let markup = show_settings_markup(value)
      changes.push(
        if following is Some(node) {
          {
            node: root.id,
            offset: node.start - root.start,
            length: 0,
            xml: markup,
          }
        } else {
          insertion(root, markup)
        },
      )
    }
    let (document, edit) = tree.document.edit_source(changes)
    parts[tree.part] = document
    edits.push((tree.part, edit))
  } else {
    self.create_show_properties(value, parts, created, edits)
  }
  ignore(self.read_show_settings(parts~))
  self.commit_slides(
    self.main,
    self.slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}

///|
fn Session::sync_show_range(
  self : Session,
  count : Int,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  guard count < self.slides.length() && self.show_properties() is Some(previous) else {
    return
  }
  let tree = Tree::new(
    previous.part,
    parts.get(previous.part).unwrap_or(previous.document),
  )
  guard tree.one(tree.root("presentationPr").id, "showPr", uri=presentation_uri)
    is Some(show) &&
    tree.one(show.id, "sldRg", uri=presentation_uri) is Some(range) else {
    return
  }
  let first = number(range.attribute("st").unwrap_or(""), 1, 256).to_int()
  let last = number(range.attribute("end").unwrap_or(""), 1, 256).to_int()
  if last <= count {
    return
  }
  let changes = [
    attribute_change({ tree, node: range, }, "st", first.min(count).to_string()),
    attribute_change({ tree, node: range, }, "end", last.min(count).to_string()),
  ]
  let (document, edit) = tree.document.edit_source(changes)
  parts[tree.part] = document
  edits.push((tree.part, edit))
}
