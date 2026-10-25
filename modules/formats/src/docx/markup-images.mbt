///|
fn MarkupInput::image(
  self : MarkupInput,
  source : String,
  alt : String,
  title : String,
  width? : Double,
  height? : Double,
) -> Unit raise @failure.Failure {
  guard alt.length() <= 1024 && title.length() <= 1024 && self.drawings < 256 else {
    @failure.reject("limit-exceeded", "Markup image metadata exceeds budget")
  }
  let comma = source
    .find(",")
    .unwrap_or_else(() => {
      @failure.reject(
        "unsupported-input", "Markup pictures require embedded PNG or JPEG data",
      )
    })
  let header = source[:comma].to_owned().to_lower()
  guard ["data:image/png;base64", "data:image/jpeg;base64"].contains(header) else {
    @failure.reject(
      "unsupported-input", "Markup pictures require embedded PNG or JPEG data",
    )
  }
  let bytes = @base64.decode(source[comma + 1:]) catch {
    _ => @failure.reject("invalid-image", "Invalid embedded image data")
  }
  let (_, mime, pixels_x, pixels_y) = @image.type_info(bytes)
  guard header == "data:" + mime + ";base64" else {
    @failure.reject(
      "invalid-image", "Embedded image MIME differs from its source",
    )
  }
  self.drawings += 1
  self.pictureBytes += bytes.length()
  guard self.pictureBytes <= 2097152 else {
    @failure.reject("limit-exceeded", "Markup images exceed byte budget")
  }
  let w = width.unwrap_or_else(() => {
    height
    .map(h => h * pixels_x.to_double() / pixels_y.to_double())
    .unwrap_or(pixels_x.to_double() * 0.75)
  })
  let h = height.unwrap_or(w * pixels_y.to_double() / pixels_x.to_double())
  guard [w, h].all(v => !v.is_nan() && !v.is_inf() && v >= 0.1 && v <= 14400) else {
    @failure.reject("invalid-image", "Invalid markup picture dimensions")
  }
  if self.mode == "text" {
    self.text(alt, CharacterFormat::new())
    return
  }
  self.add(
    "<od:r>" +
    picture_markup(
      self.drawings,
      "image",
      w,
      h,
      alt~,
      title~,
      bytes=Some(@base64.encode(bytes)),
    ) +
    "</od:r>",
  )
}

///|
fn html_picture_dimension(
  document : @html5.Document,
  id : Int,
  name : String,
) -> Double? raise @failure.Failure {
  let mut value = document.get_attribute(id, name)
  for
    declaration in document.get_attribute(id, "style").unwrap_or("").split(";") {
    let parts = declaration.split(":").to_array()
    if parts.length() == 2 && parts[0].trim().to_owned().to_lower() == name {
      value = Some(parts[1].trim().to_owned())
    }
  }
  value.map(value => {
    let value = value.trim().to_owned().to_lower()
    let pixels = value.has_suffix("px")
    let points = value.has_suffix("pt")
    let number = if pixels || points {
      value[:value.length() - 2].to_owned()
    } else {
      value
    }
    let number = @string.parse_double(number) catch {
      _ =>
        @failure.reject(
          "invalid-image", "HTML image size requires pixels or points",
        )
    }
    number * (if points { 1.0 } else { 0.75 })
  })
}

///|
/// Preflights local markup resources without changing source, selection or history.
pub fn Session::markup_images(
  self : Session,
  revision : Int,
  kind : String,
  input : String,
  mode~ : String = "source",
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let fragment = match kind {
    "html" => self.html_fragment(input, mode)
    "markdown" => self.markdown_fragment(input, mode)
    _ => @failure.reject("invalid-operation", "Unknown markup input format")
  }
  self.body_fragment_images(revision, fragment)
}
