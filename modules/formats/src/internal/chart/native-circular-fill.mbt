///|
enum CircularFill {
  Empty
  Solid(String)
  Bitmap(Bytes, String, String)
}

///|
fn circular_box(
  source : Ref,
  shadows~ : Bool = false,
) -> (CircularFill?, (String, Double)?, Int32) raise @failure.Failure {
  line_fields(
    source,
    ["solidFill", "noFill", "pattFill", "ln"] +
    (if shadows { ["effectLst"] } else { [] }),
    uri=drawing_uri,
  )
  if shadows {
    native_shadow(source)
  }
  let fills = source.tree.children
    .get(source.node.id)
    .unwrap_or([])
    .filter(node => !["ln", "effectLst"].contains(node.name))
  guard fills.length() <= 1 else {
    @failure.reject("unsupported-chart", "Ambiguous native chart fill")
  }
  let fill = fills
    .get(0)
    .map(node => {
      let fill : Ref = { tree: source.tree, node, }
      match node.name {
        "noFill" => {
          line_fields(fill, [])
          Empty
        }
        "solidFill" => Solid(line_color(fill))
        _ => {
          line_fields(
            fill,
            ["fgClr", "bgClr"],
            attributes=["prst"],
            uri=drawing_uri,
          )
          // ONLYOFFICE's hatch rows use zero for foreground and one for background.
          let mask = match node.attribute("prst") {
            Some("diagBrick") => b"\xfe\xfd\xfb\xf7\xe7\xdb\xbd\x7e"
            Some("openDmnd") => b"\x7d\xbb\xd7\xef\xd7\xbb\x7d\xfe"
            Some("pct80") => b"\x10\x00\x01\x00\x10\x00\x01\x00"
            Some("pct90") => b"\x00\x00\x00\x08\x00\x00\x00\x80"
            Some("smCheck") => b"\x66\x99\x99\x66\x66\x99\x99\x66"
            _ =>
              @failure.reject(
                "unsupported-chart", "Native hatch pattern requires support",
              )
          }
          Bitmap(
            mask,
            line_color(line_child(fill, "fgClr")),
            line_color(line_child(fill, "bgClr")),
          )
        }
      }
    })
  let (pen, join) = source
    .child("ln")
    .map(line => {
      if line.child("noFill") is Some(none) {
        line_fields(line, ["noFill"], attributes=["w"], uri=drawing_uri)
        line_fields(none, [])
        ignore(number(line.node.attribute("w").unwrap_or("0"), 0, 12700000))
        (Some(("", 0.0)), 0)
      } else {
        (
          Some(line_pen(line, round_join=true)),
          if line.child("round") is Some(_) {
            1
          } else {
            0
          },
        )
      }
    })
    .unwrap_or((None, 0))
  (fill, pen, join)
}

///|
fn circular_bool(
  source : Ref?,
  default~ : Bool = false,
) -> Bool raise @failure.Failure {
  guard source is Some(source) else { return default }
  line_fields(source, [], attributes=["val"])
  match source.node.attribute("val").unwrap_or("1") {
    "1" | "true" => true
    "0" | "false" => false
    _ => @failure.reject("unsupported-chart", "Invalid native chart boolean")
  }
}

///|
fn CircularFill::paint(
  self : CircularFill,
  out : Array[@layout.PositionedPrimitive],
  rect : @layout.Border,
) -> Unit {
  match self {
    Empty => ()
    Solid(color) =>
      out.push(
        Rectangle({
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
          color,
        }),
      )
    Bitmap(mask, zero, one) =>
      out.push(PatternRectangle(rect, 6, mask, zero, one, screen_device=true))
  }
}
