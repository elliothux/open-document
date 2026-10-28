///|
fn picture_emu(value : Double) -> String {
  (value * 12700).round().to_int64().to_string()
}

///|
fn picture_mark_source(
  name : String,
  x : Double,
  y : Double,
  dimensions : Dimensions,
) -> String {
  let col = dimensions.columns.locate(x)
  let row = dimensions.rows.locate(y)
  "<odXdr:\{name}><odXdr:col>\{col-1}</odXdr:col><odXdr:colOff>\{picture_emu(x-dimensions.columns.position(col))}</odXdr:colOff><odXdr:row>\{row-1}</odXdr:row><odXdr:rowOff>\{picture_emu(y-dimensions.rows.position(row))}</odXdr:rowOff></odXdr:\{name}>"
}

///|
fn picture_frame_source(
  anchor : String,
  rect : @layout.Border,
  picture : String,
  dimensions : Dimensions,
  client_data~ : String = "<odXdr:clientData/>",
) -> String {
  let kind = match anchor {
    "fixed" => "absoluteAnchor"
    "move" => "oneCellAnchor"
    _ => "twoCellAnchor"
  }
  let start = if anchor == "fixed" {
    "<odXdr:pos x=\"\{picture_emu(rect.x)}\" y=\"\{picture_emu(rect.y)}\"/>"
  } else {
    picture_mark_source("from", rect.x, rect.y, dimensions)
  }
  let end = if anchor == "size" {
    picture_mark_source(
      "to",
      rect.x + rect.width,
      rect.y + rect.height,
      dimensions,
    )
  } else {
    "<odXdr:ext cx=\"\{picture_emu(rect.width)}\" cy=\"\{picture_emu(rect.height)}\"/>"
  }
  "<odXdr:\{kind} xmlns:odXdr=\"\{picture_uri}\">\{start}\{end}\{picture}\{client_data}</odXdr:\{kind}>"
}

///|
fn picture_transform(rect : @layout.Border) -> String {
  "<odA:xfrm xmlns:odA=\"\{picture_drawing_uri}\"><odA:off x=\"\{picture_emu(rect.x)}\" y=\"\{picture_emu(rect.y)}\"/><odA:ext cx=\"\{picture_emu(rect.width)}\" cy=\"\{picture_emu(rect.height)}\"/></odA:xfrm>"
}

///|
fn check_picture_rect(
  anchor : String,
  rect : @layout.Border,
  dimensions : Dimensions,
) -> Unit raise @failure.Failure {
  guard ["fixed", "move", "size"].contains(anchor) &&
    [rect.x, rect.y, rect.width, rect.height].all(v => {
      !v.is_nan() && !v.is_inf() && v >= 0
    }) &&
    rect.width >= 0.1 &&
    rect.height >= 0.1 &&
    rect.width <= 14400 &&
    rect.height <= 14400 &&
    rect.x + rect.width <= dimensions.columns.position(16385) &&
    rect.y + rect.height <= dimensions.rows.position(1048577) else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet picture position or dimensions",
    )
  }
}

///|
fn Tree::picture_markup(
  self : Tree,
  id : Int32,
) -> String raise @failure.Failure {
  let node = self.nodes[id]
  let chain : Array[@xml.Node] = []
  for parent = id; parent >= 0; parent = self.nodes[parent].parent {
    chain.push(self.nodes[parent])
  }
  let bindings : Map[String, String] = Map([])
  for node in chain.rev() {
    for (prefix, uri) in node.namespaces {
      bindings[prefix] = uri
    }
  }
  let attributes = bindings
    .keys()
    .to_array()
    .filter(prefix => !node.namespaces.any(pair => pair.0 == prefix))
    .map(prefix => {
      " \{if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }}=\"\{escaped_attribute(bindings[prefix])}\""
    })
    .join("")
  let source = self.document.source()
  let end = node.opening_end - (if node.empty { 2 } else { 1 })
  source[node.start:end].to_owned() +
  attributes +
  source[end:node.end].to_owned()
}

///|
fn check_picture_text(
  name : String,
  description : String,
) -> Unit raise @failure.Failure {
  guard !name.trim().is_empty() &&
    name.length() <= 255 &&
    description.length() <= 1024 &&
    @xml.valid_text(name) &&
    @xml.valid_text(description) else {
    @failure.reject(
      "invalid-text", "Picture name or alternative text exceeds limits",
    )
  }
}

///|
fn picture_key(part : String) -> String {
  "xlsxPicture:" + part
}

///|
fn Session::new_picture_part(
  self : Session,
  bytes : Bytes,
) -> (String, String) raise @failure.Failure {
  let (extension, mime, _, _) = @image.type_info(bytes)
  let directory = self.main.split("/").map(p => p.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  for i in 1..<=self.budget.entries {
    let part = prefix + "media/odPicture\{self.revision+1}_\{i}.\{extension}"
    if !self.opc.names.contains(part.to_lower()) &&
      !self.media.contains(part) &&
      !self.parts.contains(part) {
      return (part, mime)
    }
  }
  @failure.reject("limit-exceeded", "Worksheet image part identities exhausted")
}

///|
pub fn Session::picture_resource(
  self : Session,
  revision : Int32,
  bytes : Bytes,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let (part, _) = self.new_picture_part(bytes)
  { "revision": revision, "key": picture_key(part) }
}

///|
pub fn Session::pictures(
  self : Session,
  revision : Int32,
  sheet : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let sheet = self.sheets[self.sheet_index(sheet)]
  let dimensions = self.resolved_dimensions(sheet, probe, profile)
  let mut reason = self.dimension_reason(sheet)
  let entries = self.sheet_pictures(sheet, dimensions) catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) => {
      reason = message
      []
    }
  }
  self.font_context = Some((probe, profile.copy()))
  {
    "revision": revision,
    "sheet": sheet.id,
    "reason": reason,
    "items": entries.map(fn(p : SheetObject) -> Json {
      {
        "id": p.id,
        "name": p.name,
        "description": p.description,
        "anchor": p.anchor,
        "x": p.rect.x,
        "y": p.rect.y,
        "width": p.rect.width,
        "height": p.rect.height,
        "crop": p.crop,
        "key": picture_key(p.media.unwrap()),
      }
    }),
  }
}

///|
pub fn Session::picture_image(
  self : Session,
  revision : Int32,
  key : String,
) -> Bytes raise @failure.Failure {
  self.check_revision(revision)
  guard key.has_prefix("xlsxPicture:") else {
    @failure.reject("missing-image", "Unknown worksheet image key")
  }
  let part = key[12:].to_owned()
  guard self
    .relationships()
    .any(rel => {
      rel.kind == relationship_uri + "image" &&
      !rel.external &&
      rel.target == part
    }) else {
    @failure.reject("missing-image", "Unreferenced worksheet image")
  }
  self.picture_bytes(part)
}
