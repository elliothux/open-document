///|
priv struct SlicerButtonStyle {
  fill : String
  gradient : Array[@layout.GradientStop]
  border : String
  color : String
}

///|
priv struct SlicerPalette {
  frame : String
  header : String
  text : String
  buttons : Array[SlicerButtonStyle]
}

///|
// Preset color and tint facts were checked against ONLYOFFICE ReadDefSlicerStyles.
fn slicer_builtin_palette(
  name : String,
  theme : Array[String],
) -> SlicerPalette raise @failure.Failure {
  let light = name.has_prefix("SlicerStyleLight")
  let dark = name.has_prefix("SlicerStyleDark")
  let (frame, header, fills, borders, colors, gradients) = if light || dark {
    let prefix = if light { "SlicerStyleLight" } else { "SlicerStyleDark" }
    let index = natural(name[prefix.length():].to_owned(), 6)
    guard index > 0 && name == prefix + index.to_string() else {
      @failure.reject("unsupported-drawing", "Unknown slicer preset style")
    }
    let accent = theme[index + 3]
    let pale = color_tint(accent, 0.5999938962981048)
    if light {
      (
        accent,
        accent,
        ["ffffff", pale, "ffffff", color_tint(accent, 0.7999816888943144)],
        ["cccccc", "999999", "e0e0e0", "cccccc"],
        ["000000", "000000", "828282", "828282"],
        [[], [], [], []],
      )
    } else {
      (
        accent,
        accent,
        ["c0c0c0", accent, "dfdfdf", pale],
        ["c0c0c0", accent, "dfdfdf", pale],
        ["000000", theme[0], "959595", color_tint(accent, -0.249977111117893)],
        [[], [], [], []],
      )
    }
  } else if name == "SlicerStyleOther1" {
    (
      color_tint(theme[0], -0.499984740745262),
      color_tint(theme[0], -0.3499862666707358),
      [
        theme[0],
        color_tint(theme[0], -0.249977111117893),
        theme[0],
        color_tint(theme[0], -0.1499984740745262),
      ],
      ["cccccc", "999999", "e0e0e0", "cccccc"],
      ["000000", "000000", "959595", theme[1]],
      [[], [], [], []],
    )
  } else if name == "SlicerStyleOther2" {
    let stops = [
      (-1512466, -460550),
      (-6046753, -3481866),
      (-854794, -65794),
      (-3022603, -1445125),
    ].map(pair => {
      [pair.0, pair.1].mapi((at, color) => {
        let hex = (color & 0xffffff).to_string(radix=16)
        @layout.GradientStop::{
          position: at.to_double(),
          color: "000000"[:6 - hex.length()].to_owned() + hex,
          opacity: 1,
        }
      })
    })
    (
      "4f81bd",
      "4f81bd",
      ["", "", "", ""],
      ["cccccc", "999999", "e0e0e0", "cccccc"],
      ["000000", "000000", "828282", "828282"],
      stops,
    )
  } else {
    @failure.reject(
      "unsupported-drawing", "Slicer style requires rendering support",
    )
  }
  let buttons : Array[SlicerButtonStyle] = []
  for at in 0..<4 {
    buttons.push({
      fill: fills[at],
      gradient: gradients[at],
      border: borders[at],
      color: colors[at],
    })
  }
  for _ in 0..<4 {
    buttons.push({
      fill: "",
      gradient: [
        -466590,
        if name == "SlicerStyleOther2" {
          -198668
        } else {
          -198688
        },
      ].mapi((at, color) => {
        let hex = (color & 0xffffff).to_string(radix=16)
        @layout.GradientStop::{
          position: at.to_double(),
          color: "000000"[:6 - hex.length()].to_owned() + hex,
          opacity: 1,
        }
      }),
      border: "999999",
      color: if name == "SlicerStyleOther2" {
        theme[1]
      } else {
        "000000"
      },
    })
  }
  { frame, header, text: theme[1], buttons, }
}

///|
fn Session::slicer_palette(
  self : Session,
  control : SheetSlicer,
) -> SlicerPalette raise @failure.Failure {
  let mut name = control.style
  if self.styles_part(self.parts) is Some(part) {
    let document = self.part_xml(part)
    if name.is_empty() {
      let defaults = document
        .nodes()
        .filter(node => node.uri == slicer_uri && node.name == "slicerStyles")
      guard defaults.length() <= 1 else {
        @failure.reject("unsupported-drawing", "Ambiguous default slicer style")
      }
      name = defaults
        .get(0)
        .bind(node => node.attribute("defaultSlicerStyle"))
        .unwrap_or("SlicerStyleLight1")
    }
    guard !document
      .nodes()
      .any(node => {
        (
          (node.uri == slicer_uri && node.name == "slicerStyle") ||
          (node.uri == spreadsheet_uri && node.name == "tableStyle")
        ) &&
        node.attribute("name") == Some(name)
      }) else {
      @failure.reject(
        "unsupported-drawing", "Custom slicer style requires rendering support",
      )
    }
  }
  slicer_builtin_palette(
    if name.is_empty() {
      "SlicerStyleLight1"
    } else {
      name
    },
    self.theme,
  )
}
