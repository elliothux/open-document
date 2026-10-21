///|
priv struct HtmlContext {
  format : CharacterFormat
  align : String
  rtl : Bool
  preserve : Bool
  hidden : Bool
  quote : Int
  level : Int
  list : (Int, Int)?
  first : Ref[Bool]
  heading : Int
  link : (String, String)?
}

///|
fn html_rgb(value : String) -> String raise @failure.Failure {
  let value = value.to_lower()
  let names = {
    "black": "000000",
    "white": "ffffff",
    "red": "ff0000",
    "green": "008000",
    "blue": "0000ff",
    "yellow": "ffff00",
    "gray": "808080",
    "grey": "808080",
    "silver": "c0c0c0",
    "maroon": "800000",
    "purple": "800080",
    "fuchsia": "ff00ff",
    "lime": "00ff00",
    "olive": "808000",
    "navy": "000080",
    "teal": "008080",
    "aqua": "00ffff",
  }
  if names.get(value) is Some(rgb) {
    return rgb
  }
  if value.has_prefix("#") {
    let hex = value[1:].to_owned()
    guard [3, 6].contains(hex.length()) &&
      hex.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject(
        "unsupported-input", "HTML requires a supported RGB color",
      )
    }
    return if hex.length() == 3 {
      hex.iter().map(c => c.to_string().repeat(2)).collect().join("")
    } else {
      hex
    }
  }
  if value.has_prefix("rgb(") && value.has_suffix(")") {
    let parts = value[4:value.length() - 1].split(",").to_array()
    guard parts.length() == 3 else {
      @failure.reject("unsupported-input", "HTML requires three RGB channels")
    }
    let output = StringBuilder()
    for part in parts {
      let channel = @string.parse_int(part.trim()) catch {
        _ => @failure.reject("unsupported-input", "Invalid HTML RGB channel")
      }
      guard channel >= 0 && channel <= 255 else {
        @failure.reject("unsupported-input", "Invalid HTML RGB channel")
      }
      output.write_string(channel.to_string(radix=16).pad_start(2, '0'))
    }
    return output.to_string()
  }
  @failure.reject("unsupported-input", "HTML requires a supported RGB color")
}

///|
fn html_style(
  document : @html5.Document,
  id : Int,
  original : HtmlContext,
) -> HtmlContext raise @failure.Failure {
  let tag = document.get_tag_name(id).unwrap_or("")
  let mut context = original
  let mut format = original.format
  match tag {
    "b" | "strong" => format = { ..format, bold: Set(true), }
    "i" | "em" => format = { ..format, italic: Set(true), }
    "u" => format = { ..format, underline: Set(true), }
    "s" | "strike" | "del" => format = { ..format, strike: Set(true), }
    "sup" | "sub" =>
      format = {
        ..format,
        vertAlign: Set(if tag == "sup" { "superscript" } else { "subscript" }),
      }
    "code" | "pre" => format = { ..format, family: Set("Courier New"), }
    _ => ()
  }
  if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(tag) {
    context = { ..context, heading: tag[1].to_int() - 48, }
    format = { ..format, bold: Set(true), }
  }
  if tag == "pre" {
    context = { ..context, preserve: true, }
  }
  if document.get_attribute(id, "dir") is Some(direction) {
    let direction = direction.to_lower()
    guard ["ltr", "rtl"].contains(direction) else {
      @failure.reject(
        "unsupported-input", "HTML requires an explicit text direction",
      )
    }
    context = { ..context, rtl: direction == "rtl", }
  }
  for
    declaration in document.get_attribute(id, "style").unwrap_or("").split(";") {
    if declaration.trim().is_empty() {
      continue
    }
    let parts = declaration.split(":").to_array()
    if parts.length() < 2 {
      continue
    }
    let name = parts[0].trim().to_owned().to_lower()
    let value = parts[1:]
      .map(part => part.to_owned())
      .join(":")
      .trim()
      .to_owned()
    let lower = value.to_lower()
    match name {
      "font-weight" => {
        let bold = if ["bold", "bolder"].contains(lower) {
          true
        } else if ["normal", "lighter"].contains(lower) {
          false
        } else {
          let weight = @string.parse_int(lower) catch {
            _ =>
              @failure.reject(
                "unsupported-input", "Unsupported HTML font weight",
              )
          }
          guard weight >= 100 && weight <= 900 else {
            @failure.reject("unsupported-input", "Unsupported HTML font weight")
          }
          weight >= 600
        }
        format = { ..format, bold: Set(bold), }
      }
      "font-style" => {
        guard ["normal", "italic", "oblique"].contains(lower) else {
          @failure.reject("unsupported-input", "Unsupported HTML font style")
        }
        format = { ..format, italic: Set(lower != "normal"), }
      }
      "font-size" => {
        guard lower.has_suffix("pt") || lower.has_suffix("px") else {
          @failure.reject(
            "unsupported-input", "HTML font size requires points or pixels",
          )
        }
        let number = @string.parse_double(lower[:lower.length() - 2]) catch {
          _ => @failure.reject("unsupported-input", "Invalid HTML font size")
        }
        let points = number * (if lower.has_suffix("px") { 0.75 } else { 1.0 })
        guard points >= 0.5 && points <= 1024 && !points.is_nan() else {
          @failure.reject("unsupported-input", "Invalid HTML font size")
        }
        format = { ..format, size: Set((points * 2).round() / 2), }
      }
      "font-family" => {
        let mut family = value.split(",").next().unwrap().trim().to_owned()
        if (family.has_prefix("\"") && family.has_suffix("\"")) ||
          (family.has_prefix("'") && family.has_suffix("'")) {
          family = family[1:family.length() - 1].to_owned()
        }
        guard !family.contains("(") && !family.contains("\\") else {
          @failure.reject("unsupported-input", "Unsupported HTML font family")
        }
        format = { ..format, family: Set(family), }
      }
      "color" => format = { ..format, color: Set(html_rgb(value)), }
      "text-decoration" | "text-decoration-line" => {
        let words = lower.split(" ").filter(word => !word.is_empty()).to_array()
        guard words.all(word => {
          ["none", "underline", "line-through"].contains(word.to_owned())
        }) else {
          @failure.reject(
            "unsupported-input", "Unsupported HTML text decoration",
          )
        }
        format = {
          ..format,
          underline: Set(words.contains("underline")),
          strike: Set(words.contains("line-through")),
        }
      }
      "vertical-align" => {
        guard ["baseline", "super", "sub"].contains(lower) else {
          @failure.reject(
            "unsupported-input", "Unsupported HTML vertical alignment",
          )
        }
        format = {
          ..format,
          vertAlign: Set(
            match lower {
              "super" => "superscript"
              "sub" => "subscript"
              _ => "baseline"
            },
          ),
        }
      }
      "text-align" => {
        guard ["left", "center", "right", "justify"].contains(lower) else {
          @failure.reject(
            "unsupported-input", "Unsupported HTML text alignment",
          )
        }
        context = {
          ..context,
          align: if lower == "justify" {
            "both"
          } else {
            lower
          },
        }
      }
      "white-space" => {
        guard ["normal", "nowrap", "pre", "pre-wrap", "break-spaces"].contains(
          lower,
        ) else {
          @failure.reject(
            "unsupported-input", "Unsupported HTML whitespace mode",
          )
        }
        context = {
          ..context,
          preserve: !["normal", "nowrap"].contains(lower),
        }
      }
      "display" if lower == "none" => context = { ..context, hidden: true, }
      "visibility" if ["hidden", "collapse"].contains(lower) =>
        context = { ..context, hidden: true, }
      // Only declared native formatting is imported; CSS never enters the document.
      _ => ()
    }
  }
  format.validate()
  { ..context, format, }
}
