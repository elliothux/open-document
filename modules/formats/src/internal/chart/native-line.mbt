///|
priv struct NativeLineSeries {
  color : String
  width : Double
  marker : String
  marker_size : Double
  marker_fill : String
  marker_pen : (String, Double)?
}

///|
pub struct NativeLine {
  frame_fill : String
  frame_pen : (String, Double)
  frame_default : Bool
  frame_dash : Array[Double]
  series : Array[NativeLineCurve]
  category : NativeLineAxis
  secondary_x : NativeLineAxis?
  axes : Array[NativeLineAxis]
  plot : @layout.Border?
  title : NativeLineTitle?
  plot_fill : String
  plot_pen : (String, Double)
  legend_text : @layout.TextStyle
  legend_fill : String
  legend_pen : (String, Double)
  legend_position : (Double, Double)?
  legend_bottom : Bool
  point_legend : Bool
  numeric_categories : Bool
}

///|
fn line_frame_color(text : String) -> String raise @failure.Failure {
  line_color_effect(text, 0.75, true)
}

///|
fn line_color_effect(
  text : String,
  amount : Double,
  tint : Bool,
) -> String raise @failure.Failure {
  guard worksheet_color_valid(text) && amount >= 0 && amount <= 1 else {
    @failure.reject("invalid-chart", "Invalid native chart theme color")
  }
  [0, 2, 4]
  .map(offset => {
    let value = (@string.parse_int(text[offset:offset + 2], base=16) catch {
        _ =>
          @failure.reject("invalid-chart", "Invalid native chart theme color")
      }).to_double() /
      255
    let linear = if value <= 0.04045 {
      value / 12.92
    } else {
      @math.pow((value + 0.055) / 1.055, 2.4)
    }
    let mixed = if tint {
      1.0 - (1.0 - linear) * amount
    } else {
      linear * amount
    }
    let encoded = if mixed <= 0.0031308 {
      mixed * 12.92
    } else {
      1.055 * @math.pow(mixed, 1.0 / 2.4) - 0.055
    }
    (encoded * 255)
    .round()
    .to_int()
    .max(0)
    .min(255)
    .to_string(radix=16)
    .pad_start(2, '0')
  })
  .join("")
}

///|
fn line_palette_color(
  theme : Array[String],
  index : Int64,
  maximum : Int64,
) -> String raise @failure.Failure {
  let mix = (index / 6 + 1).to_double() / (maximum / 6 + 2).to_double() * 1.4 -
    0.7
  line_color_effect(theme[4 + (index % 6).to_int()], 1 - mix.abs(), mix >= 0)
}

///|
/// Resolves native chart colors and line widths from the owning workbook theme.
pub fn WorksheetChart::with_native_theme(
  self : WorksheetChart,
  theme : Array[String],
  line_width : Double,
) -> WorksheetChart raise @failure.Failure {
  guard self.native_line is Some(_) ||
    self.native_radar is Some(_) ||
    self.native_area is Some(_) ||
    self.native_bubble is Some(_) ||
    self.native_circular is Some(_) ||
    self.native_bar is Some(_) ||
    self.native_surface is Some(_) else {
    return self
  }
  guard theme.length() == 12 &&
    theme.all(worksheet_color_valid) &&
    !line_width.is_nan() &&
    !line_width.is_inf() &&
    line_width > 0 &&
    line_width <= 1000 else {
    @failure.reject("invalid-chart", "Invalid native chart theme frame")
  }
  let background = theme[0]
  let text = theme[1]
  {
    ..self,
    native_line: self.native_line.map(line => {
      ..line,
      frame_fill: if line.frame_default {
        background.to_lower()
      } else {
        line.frame_fill
      },
      frame_pen: if line.frame_default {
        (line_frame_color(text), line_width)
      } else {
        line.frame_pen
      },
      series: line.series.map(curve => {
        if curve.paint.marker_pen is Some(_) &&
          curve.points.iter().all(point => point.1.marker_pen is Some(_)) {
          curve
        } else {
          let maximum = line.series.fold(init=curve.idx, (maximum, other) => {
            if other.axis <= curve.axis {
              maximum.max(other.idx)
            } else {
              maximum
            }
          })
          let pen = (line_palette_color(theme, curve.idx, maximum), line_width)
          {
            ..curve,
            paint: {
              ..curve.paint,
              marker_pen: Some(curve.paint.marker_pen.unwrap_or(pen)),
            },
            points: curve.points.map((_, point) => {
              ..point,
              marker_pen: Some(point.marker_pen.unwrap_or(pen)),
            }),
          }
        }
      }),
    }),
    native_bar: self.native_bar.map(bar => {
      ..bar,
      frame: (
        if bar.default_fill {
          background.to_lower()
        } else {
          bar.frame.0
        },
        if bar.default_pen {
          (line_frame_color(text), line_width)
        } else {
          bar.frame.1
        },
      ),
    }),
    native_surface: self.native_surface.map(surface => {
      ..surface,
      frame: (
        if surface.default_fill {
          background.to_lower()
        } else {
          surface.frame.0
        },
        if surface.default_pen {
          (line_frame_color(text), line_width)
        } else {
          surface.frame.1
        },
      ),
      palette: Array::makei(6, index => theme[4 + index]),
    }),
    native_radar: self.native_radar.map(radar => {
      ..radar,
      frame_fill: if radar.frame_default_fill {
        background.to_lower()
      } else {
        radar.frame_fill
      },
      frame_pen: if radar.frame_default_pen {
        (line_frame_color(text), line_width)
      } else {
        radar.frame_pen
      },
      series: radar.series.map(series => {
        ..series,
        line: {
          ..series.line,
          marker_pen: Some(
            series.line.marker_pen.unwrap_or_else(() => {
              let maximum = radar.series.fold(init=series.idx, (maximum, other) => {
                maximum.max(other.idx)
              })
              (line_palette_color(theme, series.idx, maximum), line_width)
            }),
          ),
        },
      }),
    }),
    native_area: self.native_area.map(area => {
      ..area,
      frame_fill: if area.frame_default_fill {
        background.to_lower()
      } else {
        area.frame_fill
      },
      frame_pen: if area.frame_default_pen {
        (line_frame_color(text), line_width)
      } else {
        area.frame_pen
      },
    }),
    native_bubble: self.native_bubble.map(bubble => {
      ..bubble,
      series: bubble.series.map(series => {
        ..series,
        marker_pen: (
          line_palette_color(
            theme,
            series.idx,
            bubble.series.fold(init=series.idx, (maximum, other) => {
              maximum.max(other.idx)
            }),
          ),
          line_width,
        ),
      }),
      frame_fill: if bubble.frame_default_fill {
        background.to_lower()
      } else {
        bubble.frame_fill
      },
      frame_pen: if bubble.frame_default_pen {
        (line_frame_color(text), line_width)
      } else {
        bubble.frame_pen
      },
    }),
    native_circular: self.native_circular.map(circular => {
      ..circular,
      series: circular.series.map(series => {
        ..series,
        points: series.points.mapi((index, point) => {
          ..point,
          legend_fill: line_palette_color(
            theme,
            index.to_int64(),
            (series.points.length() - 1).to_int64(),
          ),
        }),
      }),
      frame_fill: if circular.frame_default_fill {
        Solid(background.to_lower())
      } else {
        circular.frame_fill
      },
      frame_pen: if circular.frame_default_pen {
        (line_frame_color(text), line_width)
      } else {
        circular.frame_pen
      },
    }),
  }
}

///|
fn line_child(source : Ref, name : String) -> Ref raise @failure.Failure {
  source
  .child(name)
  .unwrap_or_else(() => {
    @failure.reject(
      "unsupported-chart",
      "Missing native chart text or paint: " + name,
    )
  })
}

///|
fn line_fields(
  source : Ref,
  children : Array[String],
  attributes~ : Array[String] = [],
  uri~ : String = chart_uri,
) -> Unit raise @failure.Failure {
  native_children(source, children, uri~)
  guard source.node.attributes.all(a => {
    a.uri.is_empty() && attributes.contains(a.name)
  }) else {
    @failure.reject("unsupported-chart", "Unknown native chart attribute")
  }
}

///|
fn line_real(
  value : String,
  low : Double,
  high : Double,
) -> Double raise @failure.Failure {
  let value = @string.parse_double(value) catch {
    _ => @failure.reject("unsupported-chart", "Invalid native chart number")
  }
  guard !value.is_nan() && !value.is_inf() && value >= low && value <= high else {
    @failure.reject("unsupported-chart", "Native chart number exceeds bounds")
  }
  value
}

///|
fn line_color(source : Ref) -> String raise @failure.Failure {
  line_fields(source, ["srgbClr"], uri=drawing_uri)
  let color = source
    .child("srgbClr")
    .unwrap_or_else(() => {
      @failure.reject(
        "unsupported-chart", "Native line chart requires an RGB color",
      )
    })
  line_fields(color, [], attributes=["val"])
  let value = color.node.attribute("val").unwrap_or("")
  guard worksheet_color_valid(value) else {
    @failure.reject("unsupported-chart", "Invalid native chart color")
  }
  value.to_lower()
}

///|
fn line_pen(
  source : Ref,
  round_join~ : Bool = false,
) -> (String, Double) raise @failure.Failure {
  line_fields(
    source,
    if round_join {
      ["solidFill", "prstDash", "round"]
    } else {
      ["solidFill", "prstDash"]
    },
    attributes=["w"],
    uri=drawing_uri,
  )
  if source.child("round") is Some(join) {
    line_fields(join, [])
  }
  if source.child("prstDash") is Some(dash) {
    line_fields(dash, [], attributes=["val"])
    native_flag(dash, "solid")
  }
  (
    line_color(
      source
      .child("solidFill")
      .unwrap_or_else(() => {
        @failure.reject(
          "unsupported-chart", "Native line chart requires a solid pen",
        )
      }),
    ),
    number(source.node.attribute("w").unwrap_or("9525"), 0, 12700000) / 12700,
  )
}

///|
fn line_box(
  source : Ref,
  round_join~ : Bool = false,
) -> (String, (String, Double)) raise @failure.Failure {
  line_fields(source, ["solidFill", "ln"], uri=drawing_uri)
  (
    source.child("solidFill").map(line_color).unwrap_or(""),
    source
    .child("ln")
    .map(line => line_pen(line, round_join~))
    .unwrap_or(("", 0)),
  )
}

///|
fn line_text(source : Ref) -> @layout.TextStyle raise @failure.Failure {
  line_fields(source, ["bodyPr", "lstStyle", "p"], uri=drawing_uri)
  let body = line_child(source, "bodyPr")
  line_fields(body, [], attributes=["rot", "vert", "wrap"])
  guard body.node.attribute("rot").unwrap_or("0") == "0" &&
    body.node.attribute("vert").unwrap_or("horz") == "horz" &&
    body.node.attribute("wrap").unwrap_or("square") == "square" else {
    @failure.reject(
      "unsupported-chart", "Native chart text direction requires support",
    )
  }
  line_fields(line_child(source, "lstStyle"), [])
  let paragraph = line_child(source, "p")
  line_fields(paragraph, ["pPr", "endParaRPr"], uri=drawing_uri)
  let properties = line_child(paragraph, "pPr")
  line_fields(properties, ["defRPr"], attributes=["rtl"], uri=drawing_uri)
  guard [None, Some("0"), Some("false")].contains(
    properties.node.attribute("rtl"),
  ) else {
    @failure.reject(
      "unsupported-chart", "Native chart RTL text requires support",
    )
  }
  if paragraph.child("endParaRPr") is Some(end) {
    line_fields(end, [], attributes=["lang"])
  }
  line_text_style(line_child(properties, "defRPr"))
}

///|
fn line_text_style(
  text : Ref,
  fallback_color~ : String? = None,
) -> @layout.TextStyle raise @failure.Failure {
  line_fields(
    text,
    ["solidFill", "latin", "ea", "cs", "uFillTx"],
    attributes=["sz", "b", "i", "u", "strike", "lang"],
    uri=drawing_uri,
  )
  if text.child("uFillTx") is Some(fill) {
    line_fields(fill, [])
  }
  for
    (name, values) in [
      ("u", ["none", "sng"]),
      ("strike", ["noStrike", "sngStrike"]),
    ] {
    guard values.contains(text.node.attribute(name).unwrap_or(values[0])) else {
      @failure.reject(
        "unsupported-chart", "Native chart text decoration requires support",
      )
    }
  }
  let font = line_child(text, "latin").node.attribute("typeface").unwrap_or("")
  guard !font.is_empty() && font.length() <= 256 && !font.has_prefix("+") else {
    @failure.reject("unsupported-chart", "Invalid native chart typeface")
  }
  for name in ["latin", "ea", "cs"] {
    if text.child(name) is Some(face) {
      line_fields(face, [], attributes=["typeface"])
      guard face.node.attribute("typeface") == Some(font) else {
        @failure.reject(
          "unsupported-chart", "Mixed native chart typefaces require support",
        )
      }
    }
  }
  let flag = fn(name : String) raise @failure.Failure {
    match text.node.attribute(name) {
      None | Some("0") | Some("false") => false
      Some("1") | Some("true") => true
      _ =>
        @failure.reject("unsupported-chart", "Invalid native chart font style")
    }
  }
  {
    ..@layout.TextStyle::new(
      font +
      (if flag("b") { "|bold" } else { "" }) +
      (if flag("i") { "|italic" } else { "" }),
      number(text.node.attribute("sz").unwrap_or("1000"), 100, 40900) / 100,
      if text.child("solidFill") is Some(fill) {
        line_color(fill)
      } else if fallback_color is Some(color) {
        color
      } else {
        @failure.reject("unsupported-chart", "Missing native chart text fill")
      },
    ),
    fontLeading: true,
    kerning: "none",
    underline: text.node.attribute("u") == Some("sng"),
    strike: text.node.attribute("strike") == Some("sngStrike"),
  }
}

///|
fn line_cache(source : Ref, numeric : Bool) -> Unit raise @failure.Failure {
  line_fields(source, [if numeric { "numRef" } else { "strRef" }])
  let reference = chart_child(source, if numeric { "numRef" } else { "strRef" })
  line_fields(reference, ["f", if numeric { "numCache" } else { "strCache" }])
  let formula = chart_child(reference, "f")
  line_fields(formula, [])
  guard !formula.node.text.trim().is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native chart reference cannot be empty",
    )
  }
  let cache = chart_child(
    reference,
    if numeric {
      "numCache"
    } else {
      "strCache"
    },
  )
  line_fields(cache, ["ptCount", "pt", "formatCode"])
  if cache.child("formatCode", uri=chart_uri) is Some(format) {
    line_fields(format, [])
    guard numeric && format.node.text == "General" else {
      @failure.reject(
        "unsupported-chart", "Native category number format requires support",
      )
    }
  }
  line_fields(chart_child(cache, "ptCount"), [], attributes=["val"])
  for node in cache.tree.all(cache.node.id, "pt", uri=chart_uri) {
    let point : Ref = { tree: cache.tree, node, }
    line_fields(point, ["v"], attributes=["idx"])
    line_fields(chart_child(point, "v"), [])
  }
}
