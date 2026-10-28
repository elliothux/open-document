///|
pub(all) struct TextWatermark {
  text : String
  font : String
  size : Double
  color : String
  opacity : Double
  diagonal : Bool
  bold : Bool
  italic : Bool
} derive(Eq, ToJson)

///|
pub extend TextWatermark with Eq::{equal, not_equal}

///|
pub extend TextWatermark with ToJson::{to_json}

///|
priv struct WatermarkSource {
  node : Int32
  identity : String
  value : Watermark
}

///|
pub(all) enum WatermarkImage {
  Data(Bytes)
  Resource(String)
} derive(Eq)

///|
pub extend WatermarkImage with Eq::{equal, not_equal}

///|
pub(all) enum Watermark {
  Text(TextWatermark)
  Picture(WatermarkImage, Double, Double, Double)
} derive(Eq)

///|
pub extend Watermark with Eq::{equal, not_equal}

///|
fn Watermark::normalized(self : Watermark) -> Watermark raise @failure.Failure {
  match self {
    Text(value) => Text(value.normalized())
    Picture(image, width, height, opacity) => {
      guard [width, height].all(v => {
          !v.is_nan() && !v.is_inf() && v >= 0.1 && v <= 14400
        }) &&
        opacity >= 0 &&
        opacity <= 1 else {
        @failure.reject(
          "invalid-operation", "Invalid picture watermark settings",
        )
      }
      Picture(
        image,
        (width * 12700).round() / 12700,
        (height * 12700).round() / 12700,
        (opacity * 100000).round() / 100000,
      )
    }
  }
}

///|
fn Watermark::json(self : Watermark) -> Json {
  match self {
    Text(value) => { "kind": "text", "value": Json(value) }
    Picture(Resource(key), width, height, opacity) =>
      {
        "kind": "picture",
        "image": key,
        "width": width,
        "height": height,
        "opacity": opacity,
      }
    Picture(Data(_), _, _, _) => Json::null()
  }
}

///|
fn TextWatermark::normalized(
  self : TextWatermark,
) -> TextWatermark raise @failure.Failure {
  guard !self.text.trim().is_empty() &&
    self.text.length() <= 256 &&
    @xml.valid_text(self.text) &&
    !self.text
    .iter()
    .any(c => c < ' ' || c == '\u007f' || c == '\u2028' || c == '\u2029') &&
    !self.font.trim().is_empty() &&
    self.font.length() <= 256 &&
    @xml.valid_text(self.font) &&
    !self.font
    .iter()
    .any(c => {
      c < ' ' || c == '|' || c == '\u007f' || c == '\u2028' || c == '\u2029'
    }) &&
    self.size >= 0.5 &&
    self.size <= 1638 &&
    (self.size * 2).floor() == self.size * 2 &&
    self.color.length() == 6 &&
    self.color.iter().all(c => c.is_ascii_hexdigit()) &&
    self.opacity >= 0 &&
    self.opacity <= 1 else {
    @failure.reject("invalid-operation", "Invalid text watermark settings")
  }
  {
    ..self,
    color: self.color.to_lower(),
    opacity: (self.opacity * 100000).round() / 100000,
  }
}

///|
fn TextWatermark::style(
  self : TextWatermark,
  color~ : String = self.color,
) -> @layout.TextStyle {
  @layout.TextStyle::new(
    self.font +
    (if self.bold { "|bold" } else { "" }) +
    (if self.italic { "|italic" } else { "" }),
    self.size,
    color,
  )
}

///|
fn watermark_markup(
  value : TextWatermark,
  identity : String,
  width : Double,
  height : Double,
) -> String raise @failure.Failure {
  let font = property_attribute(value.font)
  let text = property_attribute(value.text)
  let cx = (width * 12700).round().to_int64()
  let cy = (height * 12700).round().to_int64()
  let rotation = if value.diagonal { "18900000" } else { "0" }
  "<w:sdt xmlns:w='\{word_uri}' xmlns:wp='\{picture_inline_uri}' xmlns:a='\{picture_drawing_uri}' xmlns:wps='\{word_shape_uri}' xmlns:w14='http://schemas.microsoft.com/office/word/2010/wordml'><w:sdtPr><w:docPartObj><w:docPartGallery w:val='Watermarks'/><w:docPartUnique/></w:docPartObj></w:sdtPr><w:sdtContent><w:p><w:r><w:drawing><wp:anchor simplePos='0' relativeHeight='0' behindDoc='1' locked='0' layoutInCell='0' allowOverlap='1' distT='0' distB='0' distL='0' distR='0'><wp:simplePos x='0' y='0'/><wp:positionH relativeFrom='margin'><wp:align>center</wp:align></wp:positionH><wp:positionV relativeFrom='margin'><wp:align>center</wp:align></wp:positionV><wp:extent cx='\{cx}' cy='\{cy}'/><wp:wrapNone/><wp:docPr id='\{identity}' name='Text watermark'/><a:graphic><a:graphicData uri='\{word_shape_uri}'><wps:wsp><wps:cNvSpPr txBox='1'/><wps:spPr><a:xfrm rot='\{rotation}'><a:off x='0' y='0'/><a:ext cx='\{cx}' cy='\{cy}'/></a:xfrm><a:prstGeom prst='rect'><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr><wps:txbx><w:txbxContent><w:p><w:pPr><w:spacing w:before='0' w:after='0'/><w:jc w:val='center'/></w:pPr><w:r><w:rPr><w:rFonts w:ascii='\{font}' w:hAnsi='\{font}' w:eastAsia='\{font}' w:cs='\{font}'/><w:b w:val='\{if value.bold { "1" } else { "0" }}'/><w:i w:val='\{if value.italic { "1" } else { "0" }}'/><w:color w:val='\{value.color}'/><w:sz w:val='\{(value.size*2).to_int()}'/><w14:textFill><a:solidFill><a:srgbClr val='\{value.color}'><a:alpha val='\{(value.opacity*100000).round().to_int()}'/></a:srgbClr></a:solidFill></w14:textFill></w:rPr><w:t xml:space='preserve'>\{text}</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr lIns='0' rIns='0' tIns='0' bIns='0' wrap='none' anchor='ctr'><a:noAutofit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p></w:sdtContent></w:sdt>"
}

///|
fn WordTree::watermark_block(self : WordTree, id : Int32) -> Bool {
  self.nodes[id].uri == word_uri &&
  self.nodes[id].name == "sdt" &&
  self
  .descendants(id)
  .any(child => {
    self.nodes[child].uri == word_uri &&
    self.nodes[child].name == "docPartGallery" &&
    self.nodes[child].attribute("val", uri=word_uri) == Some("Watermarks")
  })
}

///|
fn watermark_equal(
  a : WordTree,
  left : Int32,
  b : WordTree,
  right : Int32,
) -> Bool {
  let x = a.nodes[left]
  let y = b.nodes[right]
  x.name == y.name &&
  x.uri == y.uri &&
  x.attributes.length() == y.attributes.length() &&
  x.attributes.all(attr => {
    y.attributes.any(other => {
      other.uri == attr.uri &&
      other.name == attr.name &&
      other.value == attr.value
    })
  }) &&
  (if x.name == "t" {
    x.text == y.text
  } else {
    x.text.trim() == y.text.trim()
  }) &&
  a.children[left].length() == b.children[right].length() &&
  a.children[left]
  .mapi((i, child) => watermark_equal(a, child, b, b.children[right][i]))
  .all(value => value)
}

///|
fn WordTree::watermark_node(
  self : WordTree,
  id : Int32,
  name : String,
  uri~ : String = word_uri,
) -> @xml.Node raise @failure.Failure {
  guard self
    .descendants(id)
    .filter(child => {
      self.nodes[child].uri == uri && self.nodes[child].name == name
    })
    is [node] else {
    @failure.reject("protected-content", "Unsupported watermark source")
  }
  self.nodes[node]
}

///|
fn watermark_number(
  node : @xml.Node,
  name : String,
  uri~ : String = "",
) -> Double raise @failure.Failure {
  let value = @string.parse_double(node.attribute(name, uri~).unwrap_or("")) catch {
    _ => @failure.reject("protected-content", "Invalid watermark coordinate")
  }
  guard !value.is_nan() && !value.is_inf() && value >= 0 && value <= 182880000 else {
    @failure.reject("protected-content", "Watermark coordinate exceeds bounds")
  }
  value
}

///|
fn WordTree::watermark_source(
  self : WordTree,
  id : Int32,
) -> WatermarkSource raise @failure.Failure {
  if self
    .descendants(id)
    .any(child => {
      self.nodes[child].uri == picture_drawing_uri &&
      self.nodes[child].name == "blip"
    }) {
    return self.picture_watermark_source(id)
  }
  let extent = self.watermark_node(id, "extent", uri=picture_inline_uri)
  let width = watermark_number(extent, "cx") / 12700
  let height = watermark_number(extent, "cy") / 12700
  let identity = self
    .watermark_node(id, "docPr", uri=picture_inline_uri)
    .attribute("id")
    .unwrap_or("")
  ignore(picture_identity(identity))
  let rotation = self
    .watermark_node(id, "xfrm", uri=picture_drawing_uri)
    .attribute("rot")
    .unwrap_or("")
  guard ["0", "18900000"].contains(rotation) && width > 0 && height > 0 else {
    @failure.reject("protected-content", "Unsupported watermark geometry")
  }
  let value : TextWatermark = {
    text: self.watermark_node(id, "t").text,
    font: self
    .watermark_node(id, "rFonts")
    .attribute("ascii", uri=word_uri)
    .unwrap_or(""),
    size: watermark_number(self.watermark_node(id, "sz"), "val", uri=word_uri) /
    2,
    color: self
    .watermark_node(id, "color")
    .attribute("val", uri=word_uri)
    .unwrap_or(""),
    opacity: watermark_number(
      self.watermark_node(id, "alpha", uri=picture_drawing_uri),
      "val",
    ) /
    100000,
    diagonal: rotation == "18900000",
    bold: self.watermark_node(id, "b").attribute("val", uri=word_uri) ==
    Some("1"),
    italic: self.watermark_node(id, "i").attribute("val", uri=word_uri) ==
    Some("1"),
  }
  let value = value.normalized()
  let expected = WordTree::new(
    @xml.Document::parse(
      @utf8.encode(watermark_markup(value, identity, width, height)),
      "watermark",
      64,
      history_byte_limit,
    ),
  )
  let source = self.source[self.nodes[id].start:self.nodes[id].end]
  guard !source.contains("<!--") &&
    !source.contains("<?") &&
    watermark_equal(self, id, expected, 0) else {
    @failure.reject("protected-content", "Extended text watermark is protected")
  }
  { node: id, identity, value: Watermark::Text(value), }
}

///|
fn WordTree::running_nodes(
  self : WordTree,
) -> Array[Int32] raise @failure.Failure {
  self.children[0].filter(id => {
    if self.watermark_block(id) {
      guard self.nodes[0].name == "hdr" else {
        @failure.reject(
          "unsupported-layout", "Footer watermarks require support",
        )
      }
      ignore(self.watermark_source(id))
      false
    } else {
      true
    }
  })
}
