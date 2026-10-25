///|
fn Object::local_connection_sites(self : Object) -> Array[(Double, Double)] {
  guard self.geometry is Some(g) &&
    supported_shape(self.preset) &&
    !line_shape(self.preset) &&
    ["sp", "pic"].contains(self.source.node.name) &&
    self.diagnostic.is_empty() else {
    return []
  }
  let w = g.width
  let h = g.height
  let sides = [(w / 2, 0.0), (0.0, h / 2), (w / 2, h), (w, h / 2)]
  match self.preset {
    "ellipse" => {
      let dx = w * 0.3535533905932738
      let dy = h * 0.3535533905932738
      [
        (w / 2, 0.0),
        (w / 2 - dx, h / 2 - dy),
        (0.0, h / 2),
        (w / 2 - dx, h / 2 + dy),
        (w / 2, h),
        (w / 2 + dx, h / 2 + dy),
        (w, h / 2),
        (w / 2 + dx, h / 2 - dy),
      ]
    }
    "triangle" => {
      let x = w * self.adjustments.0.clamp(min=0, max=1)
      [(x, 0.0), (x / 2, h / 2), (0.0, h), (x, h), (w, h), ((w + x) / 2, h / 2)]
    }
    "rtTriangle" =>
      [(0.0, 0.0), (0.0, h / 2), (0.0, h), (w / 2, h), (w, h), (w / 2, h / 2)]
    "parallelogram" | "trapezoid" => {
      let inset = w.min(h) *
        self.adjustments.0.clamp(
          min=0,
          max=polygon_adjustment_max(self.preset, w, h),
        )
      if self.preset == "trapezoid" {
        [(w / 2, 0.0), (inset / 2, h / 2), (w / 2, h), (w - inset / 2, h / 2)]
      } else {
        let y = if inset > 0 {
          (h * w / 2 / inset).clamp(min=0, max=h)
        } else {
          h
        }
        [
          (w / 2, h - y),
          ((w + inset) / 2, 0.0),
          (w - inset / 2, h / 2),
          ((w - inset) / 2, h),
          (w / 2, y),
          (inset / 2, h / 2),
        ]
      }
    }
    "chevron" | "homePlate" => {
      let inset = w.min(h) *
        self.adjustments.0.clamp(
          min=0,
          max=polygon_adjustment_max(self.preset, w, h),
        )
      let back = w - inset
      [
        (back / 2, 0.0),
        (if self.preset == "chevron" { inset } else { 0.0 }, h / 2),
        (if self.preset == "chevron" { back / 2 } else { back }, h),
        (w, h / 2),
      ]
    }
    "heptagon" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [p[3], p[4], p[5], p[6], p[0], p[1], p[2]]
    }
    "decagon" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [
        for i in 0..<10 => p[(i + 4) % 10]
      ]
    }
    "dodecagon" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [
        for i in 0..<12 => p[(i + 4) % 12]
      ]
    }
    "star7" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [p[6], p[8], p[10], p[12], p[0], p[2], p[4]]
    }
    "star16" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [
        for i in 0..<16 => p[(12 + 2 * i) % 32]
      ]
    }
    "star6" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [p[4], p[6], p[8], p[10], p[0], p[2]]
    }
    "star8" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [p[8], p[10], p[12], p[14], p[0], p[2], p[4], p[6]]
    }
    "star10" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [p[8], p[10], p[12], p[14], p[16], p[18], p[0], p[2], p[4], p[6]]
    }
    "star12" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      [
        p[10],
        p[12],
        p[14],
        p[16],
        p[18],
        p[20],
        p[22],
        p[0],
        p[2],
        p[4],
        p[6],
        p[8],
      ]
    }
    "pentagon" | "star5" => {
      let p = pentagon_points(w, h)
      if self.preset == "pentagon" {
        [p[1], p[0], p[4], (w / 2, h), p[3], p[2]]
      } else {
        [p[1], p[0], p[4], p[3], p[2]]
      }
    }
    "hexagon" | "octagon" => {
      let p = polygon_points(self.preset, w, h, self.adjustments.0)
      if self.preset == "hexagon" {
        [p[3], p[4], p[5], p[0], p[1], p[2]]
      } else {
        [p[3], p[4], p[5], p[6], p[7], p[0], p[1], p[2]]
      }
    }
    "leftRightUpArrow" => {
      let (shaft, head, _) = branched_arrow_adjustments(self.adjustments)
      let side = w.min(h)
      let center = h - side * head
      [
        (w / 2, 0.0),
        (0.0, center),
        (w / 2, center + side * shaft / 2),
        (w, center),
      ]
    }
    "leftArrow" | "rightArrow" | "notchedRightArrow" => {
      let inset = (w.min(h) * self.adjustments.1).clamp(min=0, max=w)
      let x = if self.preset == "leftArrow" { inset } else { w - inset }
      let notch = if self.preset == "notchedRightArrow" {
        inset * self.adjustments.0.clamp(min=0, max=1)
      } else {
        0.0
      }
      [(x, 0.0), (notch, h / 2), (x, h), (w, h / 2)]
    }
    "upArrow" | "downArrow" => {
      let inset = (w.min(h) * self.adjustments.1).clamp(min=0, max=h)
      let y = if self.preset == "upArrow" { inset } else { h - inset }
      [(w / 2, 0.0), (0.0, y), (w / 2, h), (w, y)]
    }
    "leftRightArrow" => {
      let inset = (w.min(h) * self.adjustments.1).clamp(min=0, max=w / 2)
      [
        (w, h / 2),
        (w - inset, h),
        (inset, h),
        (0.0, h / 2),
        (inset, 0.0),
        (w - inset, 0.0),
      ]
    }
    "upDownArrow" => {
      let inset = (w.min(h) * self.adjustments.1).clamp(min=0, max=h / 2)
      let half = w * self.adjustments.0.clamp(min=0, max=1) / 2
      [
        (w / 2, 0.0),
        (0.0, inset),
        (w / 2 - half, h / 2),
        (0.0, h - inset),
        (w / 2, h),
        (w, h - inset),
        (w / 2 + half, h / 2),
        (w, inset),
      ]
    }
    _ => sides
  }
}
