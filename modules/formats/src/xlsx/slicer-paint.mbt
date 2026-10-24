///|
priv struct SlicerGeometry {
  header : Double
  body : @layout.Border
  buttons : Array[(Int, @layout.Border)]
  scroll : @layout.Border?
  thumb : @layout.Border?
  clear : @layout.Border?
  multi : @layout.Border?
  previous : @layout.Border?
  next : @layout.Border?
  maximum : Int
  page : Int
}

///|
fn SlicerDrawing::geometry(
  self : SlicerDrawing,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> SlicerGeometry raise @failure.Failure {
  let control = self.control
  let header = if control.show_caption {
    let block = probe.text_block(
      control.caption,
      @layout.TextStyle::new(self.font + "|bold", self.size, self.palette.text),
      profile,
      (width - 46.2).max(0.01),
      false,
    )
    (block.height + 3.6).max(15 + 72.0 / 25.4)
  } else {
    0.0
  }
  let gap = 7.2 * 14 / 37
  let body : @layout.Border = {
    x: 7.2,
    y: header + 3.6,
    width: (width - 14.4).max(0),
    height: (height - header - 10.8).max(0),
  }
  let rows = (control.cache.members.length() + control.columns - 1) /
    control.columns
  let full = ((body.height + gap) / (control.row_height + gap))
    .floor()
    .to_int()
    .max(1)
    .min(rows.max(1))
  let overflow = rows.to_double() * control.row_height +
    (rows - 1).max(0).to_double() * gap >
    body.height
  let button_width = (body.width -
    (control.columns - 1).to_double() * gap -
    (if overflow { 11.25 + gap } else { 0 })).max(0) /
    control.columns.to_double()
  let buttons : Array[(Int, @layout.Border)] = []
  for index in control.start..<control.cache.members.length() {
    let position = index - control.start
    let y = body.y +
      (position / control.columns).to_double() * (control.row_height + gap)
    if y >= body.y + body.height {
      break
    }
    if button_width > 0 {
      buttons.push(
        (
          index,
          {
            x: body.x +
            (position % control.columns).to_double() * (button_width + gap),
            y,
            width: button_width,
            height: control.row_height,
          },
        ),
      )
    }
  }
  let scroll : @layout.Border? = if overflow &&
    body.width >= 11.25 &&
    body.height > 0 {
    Some({
      x: body.x + body.width - 11.25,
      y: body.y,
      width: 11.25,
      height: body.height,
    })
  } else {
    None
  }
  let thumb = scroll.map(track => {
    let rail = (track.height - 22.5).max(0)
    let total = rows.to_double() * control.row_height +
      (rows - 1).max(0).to_double() * gap
    let thumb_height = (rail * rail / total).max(rail / 4).min(rail)
    let progress = (control.start.to_double() /
    control.columns.to_double() /
    (rows - full).max(1).to_double()).min(1)
    {
      ..track,
      y: track.y +
      11.25.min(track.height / 2) +
      (rail - thumb_height) * progress,
      height: thumb_height,
    }
  })
  let clear = if header > 0 {
    Some(@layout.Border::{
      x: width - 22.2,
      y: header / 2 - 7.5,
      width: 15,
      height: 15,
    })
  } else {
    None
  }
  {
    header,
    body,
    buttons,
    scroll,
    thumb,
    clear,
    multi: clear.map(rect => { ..rect, x: width - 39, }),
    previous: scroll.map(rect => { ..rect, height: 11.25.min(rect.height / 2), }),
    next: scroll.map(rect => {
      ..rect,
      y: rect.y + rect.height - 11.25.min(rect.height / 2),
      height: 11.25.min(rect.height / 2),
    }),
    maximum: (rows - full).max(0) * control.columns,
    page: full,
  }
}

///|
fn SlicerDrawing::paint_text(
  self : SlicerDrawing,
  primitives : Array[@layout.PositionedPrimitive],
  text : String,
  rect : @layout.Border,
  color : String,
  bold : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Unit raise @failure.Failure {
  if text.is_empty() || rect.width <= 0 || rect.height <= 0 {
    return
  }
  let block = probe.text_block(
    text,
    @layout.TextStyle::new(
      self.font + (if bold { "|bold" } else { "" }),
      self.size,
      color,
    ),
    profile,
    rect.width,
    false,
  )
  primitives.push(Clip(rect))
  primitives.push(
    Transform({
      a: 1,
      b: 0,
      c: 0,
      d: 1,
      e: rect.x,
      f: rect.y + (rect.height - block.height).max(0) / 2,
    }),
  )
  for line in block.lines {
    primitives.append(line)
  }
  primitives.push(Restore)
  primitives.push(Restore)
}

///|
// Native header padding and row/column spacing follow ONLYOFFICE SlicerView.js.
fn SlicerDrawing::paint(
  self : SlicerDrawing,
  primitives : Array[@layout.PositionedPrimitive],
  rect : @layout.Border,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  hover~ : Int? = None,
) -> Unit raise @failure.Failure {
  let geometry = self.geometry(rect.width, rect.height, probe, profile)
  primitives.push(Clip(rect))
  primitives.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: rect.x, f: rect.y, }))
  let frame : @layout.Border = {
    x: 0.375,
    y: 0.375,
    width: (rect.width - 0.75).max(0),
    height: (rect.height - 0.75).max(0),
  }
  primitives.push(
    Rectangle({
      x: 0,
      y: 0,
      width: rect.width,
      height: rect.height,
      color: "ffffff",
    }),
  )
  primitives.push(Stroke(frame, self.palette.frame, 0.75))
  if geometry.header > 0 {
    self.paint_text(
      primitives,
      self.control.caption,
      {
        x: 7.2,
        y: 1.8,
        width: (rect.width - 46.2).max(0),
        height: (geometry.header - 3.6).max(0),
      },
      self.palette.text,
      true,
      probe,
      profile,
    )
    primitives.push(
      Stroke(
        { x: 0, y: geometry.header, width: rect.width, height: 0, },
        self.palette.header,
        0.75,
      ),
    )
  }
  primitives.push(Clip(geometry.body))
  for (index, button) in geometry.buttons {
    let item = self.control.cache.members[index]
    let style = self.palette.buttons[(if item.selected { 1 } else { 0 }) +
      (if item.hasData { 0 } else { 2 }) +
      (if hover == Some(item.index) { 4 } else { 0 })]
    if style.gradient.is_empty() {
      primitives.push(
        Rectangle({
          x: button.x,
          y: button.y,
          width: button.width,
          height: button.height,
          color: style.fill,
        }),
      )
    } else {
      primitives.push(
        Transform({ a: 0, b: 1, c: 1, d: 0, e: button.x, f: button.y, }),
      )
      primitives.push(
        GradientRectangle(
          { x: 0, y: 0, width: button.height, height: button.width, },
          style.gradient,
        ),
      )
      primitives.push(Restore)
    }
    primitives.push(Stroke(button, style.border, 0.75))
    self.paint_text(
      primitives,
      if item.value == Blank {
        "(blank)"
      } else {
        item.value.display()
      },
      { ..button, x: button.x + 7.2, width: (button.width - 14.4).max(0), },
      style.color,
      false,
      probe,
      profile,
    )
  }
  if geometry.scroll is Some(track) {
    primitives.push(
      Rectangle({
        x: track.x,
        y: track.y,
        width: track.width,
        height: track.height,
        color: "f0f0f0",
      }),
    )
  }
  if geometry.thumb is Some(thumb) {
    primitives.push(
      Rectangle({
        x: thumb.x + 0.75,
        y: thumb.y,
        width: (thumb.width - 1.5).max(0),
        height: thumb.height,
        color: "bcbcbc",
      }),
    )
  }
  for (up, button) in [(true, geometry.previous), (false, geometry.next)] {
    if button is Some(button) {
      let middle = button.y + button.height / 2
      primitives.push(
        Path(
          [
            Move(button.x + 3, middle + (if up { 1.5 } else { -1.5 })),
            Line(
              button.x + button.width / 2,
              middle + (if up { -1.5 } else { 1.5 }),
            ),
            Line(
              button.x + button.width - 3,
              middle + (if up { 1.5 } else { -1.5 }),
            ),
            Close,
          ],
          "666666",
          "",
          0,
          {
            fillAlpha: 1,
            strokeAlpha: 1,
            dash: [],
            cap: 0,
            join: 0,
            miter: 10,
          },
        ),
      )
    }
  }
  primitives.push(Restore)
  if geometry.clear is Some(button) {
    primitives.push(
      Transform({ a: 1, b: 0, c: 0, d: 1, e: button.x, f: button.y, }),
    )
    primitives.push(
      Path(
        [
          Move(2, 3),
          Line(12, 3),
          Line(8, 7),
          Line(8, 12),
          Line(6, 10),
          Line(6, 7),
          Close,
        ],
        "444444",
        "",
        0,
        { fillAlpha: 1, strokeAlpha: 1, dash: [], cap: 0, join: 0, miter: 10, },
      ),
    )
    primitives.push(Restore)
  }
  if geometry.multi is Some(button) {
    for at in 0..<3 {
      let y = button.y + 3 + at.to_double() * 4
      primitives.push(
        Stroke({ x: button.x + 2, y, width: 2, height: 2, }, "444444", 0.75),
      )
      primitives.push(
        Stroke(
          { x: button.x + 7, y: y + 1, width: 6, height: 0, },
          "444444",
          0.75,
        ),
      )
    }
  }
  primitives.push(Restore)
  primitives.push(Restore)
}
