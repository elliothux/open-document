///|
priv struct DrawingFragment {
  object : SheetObject
  image : Bytes?
  data : @xml.Document?
}

///|
fn SheetObject::check_fragment_identity(
  self : SheetObject,
) -> @xml.Node raise @failure.Failure {
  check_picture_text(self.name, self.description)
  guard self.chart is Some(_) || self.source.attributes.is_empty() else {
    @failure.reject(
      "protected-content", "Drawing clipboard bindings or macros require support",
    )
  }
  self.transfer_identity(true)
}

///|
fn drawing_fragment_dimensions() -> Dimensions {
  {
    rows: { default_size: 14401, spans: [], limit: 1048576, },
    columns: { default_size: 14401, spans: [], limit: 16384, },
    automatic_rows: Map([]),
    automatic_columns: [],
  }
}

///|
pub fn Session::capture_drawing(
  self : Session,
  revision : Int,
  sheet : String,
  id : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard id.length() <= 10 else {
    @failure.reject("invalid-operation", "Invalid worksheet drawing identity")
  }
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let object = self
    .sheet_objects(current, self.resolved_dimensions(current, probe, profile))
    .iter()
    .find_first(object => object.id == id)
    .unwrap_or_else(() => {
      @failure.reject("invalid-operation", "Worksheet drawing no longer exists")
    })
  let identity = object.check_fragment_identity()
  let changes = object.transfer_changes(
    identity,
    "1",
    { ..object.rect, x: 0, y: 0, },
    drawing_fragment_dimensions(),
  )
  let (document, _) = object.tree.document.edit_source(changes)
  let image = object.media.map(part => self.picture_bytes(part))
  guard image.map(bytes => bytes.length() <= 2097152).unwrap_or(true) else {
    @failure.reject("limit-exceeded", "Copied drawing image exceeds 2MiB")
  }
  let frame = Tree::new(document).picture_markup(object.frame.id)
  guard frame.length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Copied drawing source exceeds budget")
  }
  let chart : Json = if object.chart is Some((part, chart)) {
    let original = self.part_xml(part)
    guard !self.relationships().any(link => link.owner == part) &&
      !original.source().contains("<!--") &&
      !original.source()[original.nodes()[0].start:].contains("<?") else {
      @failure.reject(
        "protected-content", "Chart resources or annotations require clipboard support",
      )
    }
    let visible = object.chart_visibility.unwrap()
    {
      "source": chart.markup(),
      "visible": ToJson::to_json([visible.categories] + visible.values),
    }
  } else {
    Json::null()
  }
  let payload : Json = {
    "frame": frame,
    "theme": self.theme,
    "font": self.normal_font,
    "image": image
    .map(bytes => Json(@base64.encode(bytes)))
    .unwrap_or(Json::null()),
    "chart": chart,
  }
  let fragment = payload.stringify()
  guard fragment.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "Drawing clipboard exceeds budget")
  }
  {
    "fragment": fragment,
    "text": object.shape
    .map(shape => shape.text)
    .filter(text => !text.is_empty())
    .unwrap_or(object.name),
  }
}

///|
fn read_drawing_fragment(
  source : String,
  budget : @archive.Budget,
) -> DrawingFragment raise @failure.Failure {
  guard source.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "Drawing clipboard exceeds budget")
  }
  let json = @json.parse(source) catch {
    _ => @failure.reject("invalid-operation", "Invalid drawing clipboard JSON")
  }
  guard json is Object(fields) &&
    fields.length() == 5 &&
    json
    is {
      "frame": String(frame),
      "font": String(font),
      "theme": Array(colors),
      "image": image,
      "chart": chart,
      ..
    } &&
    frame.length() <= 1048576 &&
    !font.trim().is_empty() &&
    font.length() <= 255 &&
    @xml.valid_text(font) &&
    colors.length() == 12 else {
    @failure.reject("invalid-operation", "Invalid drawing clipboard fields")
  }
  let theme = colors.map(value => {
    guard value is String(value) && value.length() == 6 else {
      @failure.reject(
        "invalid-operation", "Drawing clipboard theme requires RGB colors",
      )
    }
    ignore(color_hex(value))
    value
  })
  let bytes = match image {
    Null => None
    String(encoded) => {
      guard encoded.length() <= 2796204 else {
        @failure.reject("limit-exceeded", "Copied drawing image exceeds 2MiB")
      }
      let bytes = @base64.decode(encoded) catch {
        _ =>
          @failure.reject(
            "invalid-operation", "Invalid drawing clipboard image",
          )
      }
      guard bytes.length() <= 2097152 else {
        @failure.reject("limit-exceeded", "Copied drawing image exceeds 2MiB")
      }
      ignore(@image.type_info(bytes))
      Some(bytes)
    }
    _ =>
      @failure.reject(
        "invalid-operation", "Drawing clipboard image must be bytes or null",
      )
  }
  let seed = Session::create(budget)
  defer seed.close()
  let parts = seed.parts.copy()
  let media = seed.media.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let (part, drawing_relation) = seed.create_sheet_resource(
    seed.sheets[0].id,
    "drawing",
    "<xdr:wsDr xmlns:xdr=\"\{picture_uri}\">\{frame}</xdr:wsDr>",
    parts,
    created,
    edits,
  )
  let (document, _) = insert_sheet_drawing(
    seed.sheets[0].document,
    drawing_relation,
    name="drawing",
  )
  let mut document = document
  let data = read_chart_fragment(chart, budget)
  guard bytes is None || data is None else {
    @failure.reject(
      "invalid-operation", "Drawing clipboard cannot mix image and chart resources",
    )
  }
  if data is Some((chart, data)) {
    let (_, relation) = seed.create_sheet_resource(
      part,
      "chart",
      chart.markup(),
      parts,
      created,
      edits,
    )
    parts[part] = drawing_fragment_reference(
      parts[part],
      chart_uri,
      "chart",
      "id",
      relation,
    )
    document = insert_sheet_drawing(data, drawing_relation, name="drawing").0
  }
  if bytes is Some(bytes) {
    let (image_part, mime) = seed.new_picture_part(bytes)
    let relation = seed.attach_sheet_resource(
      part, image_part, "image", mime, parts, created, edits,
    )
    parts[part] = drawing_fragment_reference(
      parts[part],
      picture_drawing_uri,
      "blip",
      "embed",
      relation,
    )
    media[image_part] = bytes
  }
  let sheet = { ..seed.sheets[0], document, }
  let view = {
    ..seed,
    sheets: [sheet],
    parts,
    media,
    theme,
    normal_font: font,
  }
  let objects = view.sheet_objects(sheet, drawing_fragment_dimensions())
  guard objects is [object] &&
    (object.chart is Some(_)) == (data is Some(_)) &&
    (object.media is Some(_)) == (bytes is Some(_)) else {
    @failure.reject(
      "invalid-operation", "Drawing clipboard requires one picture or shape",
    )
  }
  ignore(object.check_fragment_identity())
  DrawingFragment::{ object, image: bytes, data: data.map(entry => entry.1), }
}

///|
pub fn Session::drawing_fragment_image(
  self : Session,
  revision : Int,
  fragment : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let decoded = read_drawing_fragment(fragment, self.budget)
  {
    "bytes": decoded.image
    .map(bytes => Json(@base64.encode(bytes)))
    .unwrap_or(Json::null()),
  }
}
