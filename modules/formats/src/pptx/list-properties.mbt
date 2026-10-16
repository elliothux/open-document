///|
pub(all) enum ListFormat {
  NoList
  Bullet(String)
  Numbered(String, Int)
} derive(Eq)

///|
pub extend ListFormat with Eq::{equal, not_equal}

///|
fn number_format(value : String) -> String {
  match value {
    "arabicPeriod" => "decimal"
    "alphaLcPeriod" => "lowerLetter"
    "alphaUcPeriod" => "upperLetter"
    "romanLcPeriod" => "lowerRoman"
    "romanUcPeriod" => "upperRoman"
    _ => ""
  }
}

///|
fn ListFormat::check(self : ListFormat) -> Unit raise @failure.Failure {
  match self {
    NoList => ()
    Bullet(value) => {
      guard !value.is_empty() &&
        value.length() <= 16 &&
        @xml.valid_text(value) &&
        !value
        .iter()
        .any(c => c <= ' ' || c == '\u007f' || c == '\u2028' || c == '\u2029') &&
        @layout.grapheme_boundaries(value).length() == 2 else {
        @failure.reject(
          "invalid-operation", "Bullet must be one visible grapheme",
        )
      }
    }
    Numbered(value, start) => {
      guard !number_format(value).is_empty() && start >= 1 && start <= 32767 else {
        @failure.reject(
          "invalid-operation", "Unsupported numbering type or start",
        )
      }
    }
  }
}

///|
fn ListFormat::query(self : ListFormat) -> Json {
  match self {
    NoList => { "kind": "none" }
    Bullet(value) => { "kind": "bullet", "value": value }
    Numbered(value, start) =>
      { "kind": "number", "value": value, "start": start }
  }
}

///|
fn check_list_properties(properties : Ref) -> Unit raise @failure.Failure {
  let kinds = properties.tree.children
    .get(properties.node.id)
    .unwrap_or([])
    .filter(n => {
      n.uri == drawing_uri &&
      ["buNone", "buChar", "buAutoNum", "buBlip"].contains(n.name)
    })
  guard kinds.length() <= 1 else {
    @failure.reject(
      "unsupported-text", "Ambiguous list definitions are protected",
    )
  }
  for node in kinds {
    let markup = source_xml({ tree: properties.tree, node, })
    guard node.name != "buBlip" &&
      node.text.trim().is_empty() &&
      !markup.contains("<!--") &&
      !markup.contains("<?") &&
      properties.tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() &&
        (match node.name {
          "buChar" => a.name == "char"
          "buAutoNum" => ["type", "startAt"].contains(a.name)
          _ => false
        })
      }) else {
      @failure.reject(
        "unsupported-text", "Extended or picture lists are protected",
      )
    }
  }
}

///|
fn read_list(styles : Array[Ref]) -> ListFormat raise @failure.Failure {
  for source in styles {
    check_list_properties(source)
    if source.child("buNone") is Some(_) {
      return NoList
    }
    if source.child("buChar") is Some(node) {
      let value = Bullet(node.node.attribute("char").unwrap_or(""))
      value.check() catch {
        _ => @failure.reject("unsupported-text", "Unsupported character bullet")
      }
      return value
    }
    if source.child("buAutoNum") is Some(node) {
      let value = Numbered(
        node.node.attribute("type").unwrap_or(""),
        number(node.node.attribute("startAt").unwrap_or("1"), 1, 32767).to_int(),
      )
      value.check() catch {
        _ => @failure.reject("unsupported-text", "Unsupported numbering type")
      }
      return value
    }
  }
  NoList
}

///|
fn list_label(
  list : ListFormat,
  level : Int,
  previous : Array[TextParagraph],
) -> String raise @failure.Failure {
  match list {
    NoList => ""
    Bullet(value) => value
    Numbered(kind, start) => {
      let mut value = start
      for i = previous.length() - 1; i >= 0; i = i - 1 {
        let paragraph = previous[i]
        if paragraph.level > level {
          continue
        }
        if paragraph.level < level || paragraph.list != list {
          break
        }
        if paragraph.runs.any(r => !r.text.is_empty()) {
          value += 1
        }
      }
      @layout.numbering_value(number_format(kind), value) + "."
    }
  }
}

///|
fn list_markup(list : ListFormat) -> (String, String) raise @failure.Failure {
  match list {
    NoList => ("buNone", "<a:buNone xmlns:a=\"\{drawing_uri}\"/>")
    Bullet(value) =>
      (
        "buChar",
        "<a:buChar xmlns:a=\"\{drawing_uri}\" char=\"\{@xml.escape_text(value).replace_all(old="\"", new="&quot;")}\"/>",
      )
    Numbered(value, start) =>
      (
        "buAutoNum",
        "<a:buAutoNum xmlns:a=\"\{drawing_uri}\" type=\"\{value}\" startAt=\"\{start}\"/>",
      )
  }
}
