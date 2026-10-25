///|
pub(all) struct PageBorder {
  side : String
  style : String
  color : String
  themeColor : String?
  width : Double
  space : Double
}

///|
pub impl ToJson for PageBorder with fn to_json(self) {
  {
    "side": self.side,
    "style": self.style,
    "color": self.color,
    "themeColor": self.themeColor.map(Json::string).unwrap_or(Json::null()),
    "width": self.width,
    "space": self.space,
  }
}

///|
pub extend PageBorder with ToJson::{to_json}

///|
pub(all) struct PageBorders {
  offsetFrom : String
  display : String
  zOrder : String
  sides : Array[PageBorder]
} derive(ToJson)

///|
pub extend PageBorders with ToJson::{to_json}

///|
pub fn PageBorders::new() -> PageBorders {
  { offsetFrom: "text", display: "allPages", zOrder: "front", sides: [], }
}

///|
pub fn PageBorders::validate(self : PageBorders) -> Unit raise @failure.Failure {
  guard ["page", "text"].contains(self.offsetFrom) &&
    ["allPages", "firstPage", "notFirstPage"].contains(self.display) &&
    ["front", "back"].contains(self.zOrder) &&
    self.sides.length() <= 4 else {
    @failure.reject("invalid-style", "Invalid page border settings")
  }
  let seen : Map[String, Bool] = Map([])
  for border in self.sides {
    guard ["top", "left", "bottom", "right"].contains(border.side) &&
      ["single", "double", "dashed", "dotted"].contains(border.style) &&
      !seen.contains(border.side) &&
      border.color.length() == 6 &&
      border.color.iter().all(c => c.is_ascii_hexdigit()) &&
      (
        border.themeColor is None ||
        [
          "dark1", "light1", "dark2", "light2", "accent1", "accent2", "accent3",
          "accent4", "accent5", "accent6", "hyperlink", "followedHyperlink", "text1",
          "text2", "background1", "background2",
        ].contains(border.themeColor.unwrap())
      ) &&
      border.width >= 0.25 &&
      border.width <= 12 &&
      border.width * 8 == (border.width * 8).round() &&
      border.space >= 0 &&
      border.space <= 31 &&
      border.space == border.space.round() else {
      @failure.reject("invalid-style", "Invalid or duplicate page border")
    }
    seen[border.side] = true
  }
}

///|
pub fn PageBorders::fills(
  self : PageBorders,
  page : PageSetup,
  index : Int,
) -> Array[Fill] raise @failure.Failure {
  self.validate()
  if (self.display == "firstPage" && index != 0) ||
    (self.display == "notFirstPage" && index == 0) {
    return []
  }
  let sides : Map[String, PageBorder] = Map([])
  for side in self.sides {
    sides[side.side] = side
  }
  let text = self.offsetFrom == "text"
  let edge = fn(side : String) {
    let border = sides.get(side)
    let space = border.map(b => b.space).unwrap_or(0)
    // Word double borders contain two lines and a gap of the declared width.
    let width = border
      .map(b => b.width * (if b.style == "double" { 3 } else { 1 }))
      .unwrap_or(0)
    match side {
      "left" => if text { page.left - space - width } else { space }
      "top" => if text { page.top - space - width } else { space }
      "right" =>
        if text {
          page.width - page.right + space + width
        } else {
          page.width - space
        }
      _ =>
        if text {
          page.height - page.bottom + space + width
        } else {
          page.height - space
        }
    }
  }
  let left = edge("left")
  let top = edge("top")
  let right = edge("right")
  let bottom = edge("bottom")
  let result : Array[Fill] = []
  // ONLYOFFICE draws vertical sides first, then horizontal sides across their corners.
  for name in ["left", "right", "top", "bottom"] {
    if sides.get(name) is Some(border) {
      let vertical = name == "left" || name == "right"
      for stripe in 0..<(if border.style == "double" { 2 } else { 1 }) {
        let inset = fn(side : String) {
          sides
          .get(side)
          .map(b => {
            if stripe == 1 && b.style == "double" {
              2.0 * b.width
            } else {
              0.0
            }
          })
          .unwrap_or(0.0)
        }
        let top_mid = top +
          inset("top") +
          sides.get("top").map(b => b.width / 2).unwrap_or(0)
        let bottom_mid = bottom -
          inset("bottom") -
          sides.get("bottom").map(b => b.width / 2).unwrap_or(0)
        let offset = if stripe == 0 { 0.0 } else { 2 * border.width }
        let rect : Fill = {
          x: if vertical {
            if name == "left" {
              left + offset
            } else {
              right - border.width - offset
            }
          } else {
            left + inset("left")
          },
          y: if vertical {
            top_mid
          } else if name == "top" {
            top + offset
          } else {
            bottom - border.width - offset
          },
          width: if vertical {
            border.width
          } else {
            right - left - inset("left") - inset("right")
          },
          height: if vertical {
            bottom_mid - top_mid
          } else {
            border.width
          },
          color: border.color,
        }
        guard rect.width > 0 && rect.height > 0 else {
          @failure.reject("layout-overflow", "Page borders cross each other")
        }
        if border.style == "dashed" || border.style == "dotted" {
          // LibreOffice border patterns use line/gap ratios16:5 and1:2.
          let dash = border.width *
            (if border.style == "dashed" { 16.0 } else { 1.0 })
          let period = dash +
            border.width * (if border.style == "dashed" { 5.0 } else { 2.0 })
          let length = if vertical { rect.height } else { rect.width }
          let count = (length / period).ceil().to_int()
          guard count <= 8192 - result.length() else {
            @failure.reject(
              "limit-exceeded", "Page border pattern exceeds8192 segments",
            )
          }
          for index in 0..<count {
            let offset = index.to_double() * period
            let size = dash.min(length - offset)
            result.push({
              ..rect,
              x: rect.x + (if vertical { 0.0 } else { offset }),
              y: rect.y + (if vertical { offset } else { 0.0 }),
              width: if vertical {
                rect.width
              } else {
                size
              },
              height: if vertical {
                size
              } else {
                rect.height
              },
            })
          }
        } else {
          guard result.length() < 8192 else {
            @failure.reject(
              "limit-exceeded", "Page border pattern exceeds8192 segments",
            )
          }
          result.push(rect)
        }
      }
    }
  }
  result
}
