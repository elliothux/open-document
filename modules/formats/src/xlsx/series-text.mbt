///|
priv struct SeriesPattern {
  prefix : String?
  padding : Int
  fit : SeriesTrend
  base : Double
  mut cursor : Int
}

///|
fn series_text_suffix(
  text : String,
) -> (String, Double, Int)? raise @failure.Failure {
  let mut end = text.length()
  while end > 0 && text[end - 1] >= 48 && text[end - 1] <= 57 {
    end -= 1
  }
  if end == text.length() {
    return None
  }
  let digits = text[end:]
  let value = @string.parse_double(digits) catch {
    _ =>
      @failure.reject(
        "invalid-operation", "Text series suffix exceeds exact integer range",
      )
  }
  guard value <= 9007199254740991.0 else {
    @failure.reject(
      "invalid-operation", "Text series suffix exceeds exact integer range",
    )
  }
  Some(
    (
      text[:end].to_owned(),
      value,
      if digits[0] == 48 {
        digits.length()
      } else {
        0
      },
    ),
  )
}

///|
fn series_pattern_group(
  indices : Array[Int],
  suffixes : Array[(String?, Double, Int)?],
  slots : Array[Int?],
  plans : Array[SeriesPattern],
  forward : Bool,
  single : Bool,
) -> Unit {
  if indices.is_empty() {
    return
  }
  let first = indices[0]
  let last = indices[indices.length() - 1]
  let (prefix, initial, _) = suffixes[first].unwrap()
  if single && prefix is None {
    return
  }
  let base = if prefix is Some(_) { initial } else { 0 }
  let mut padding = 0
  let mut regular = true
  let spacing = if indices.length() > 1 { indices[1] - first } else { 1 }
  let difference = if indices.length() > 1 {
    suffixes[indices[1]].unwrap().1 - initial
  } else {
    0
  }
  for offset, index in indices {
    padding = padding.max(suffixes[index].unwrap().2)
    if offset > 0 &&
      (
        index - indices[offset - 1] != spacing ||
        suffixes[index].unwrap().1 - suffixes[indices[offset - 1]].unwrap().1 !=
        difference
      ) {
      regular = false
    }
  }
  let stride = if regular { spacing } else { 1 }
  let points = indices.map(index => {
    (((index - first) / stride).to_double(), suffixes[index].unwrap().1 - base)
  })
  let scale = points.fold(init=1.0, (scale, p) => scale.max(p.1.abs()))
  let fit = series_fit(points, false, points[0].1, scale, 0)
  let fit = if indices.length() == 1 && !forward {
    { ..fit, slope: -1, }
  } else {
    fit
  }
  let intercept = fit.mean - fit.slope * fit.origin
  if prefix is Some(_) &&
    (fit.slope != fit.slope.trunc() || intercept != intercept.trunc()) {
    return
  }
  let plan = plans.length()
  plans.push({
    prefix,
    padding,
    fit,
    base,
    cursor: (last - first) / stride + 1,
  })
  if regular && spacing > 1 {
    for index in indices {
      slots[index] = Some(plan)
    }
  } else {
    // Irregular gaps join the sequence; regular spacing keeps the blank slots.
    for index in first..<=last {
      slots[index] = Some(plan)
    }
  }
}

///|
fn SeriesPattern::next(self : SeriesPattern) -> Value raise @failure.Failure {
  let delta = self.fit.mean +
    self.fit.slope * (self.cursor.to_double() - self.fit.origin)
  // ONLYOFFICE mirrors the signed sequence when its suffix crosses zero.
  let signed = self.base + delta * self.fit.scale
  guard !signed.is_nan() && !signed.is_inf() else {
    @failure.reject(
      "invalid-operation", "Automatic series exceeds finite numeric range",
    )
  }
  if self.prefix is None {
    self.cursor += 1
    return Number(signed)
  }
  let number = signed.abs()
  guard number <= 9007199254740991.0 && number == number.trunc() else {
    @failure.reject(
      "invalid-operation", "Text series result exceeds exact integer range",
    )
  }
  let digits = number.to_int64().to_string()
  let text = self.prefix.unwrap() +
    "0".repeat((self.padding - digits.length()).max(0)) +
    digits
  guard text.length() <= 32767 else {
    @failure.reject("limit-exceeded", "Text series exceeds cell text budget")
  }
  self.cursor += 1
  Text(text)
}

///|
fn Sheet::text_series_values(
  self : Sheet,
  source : Range,
  lane : Int,
  vertical : Bool,
  first : Int,
  last : Int,
  forward : Bool,
  automatic~ : Bool = false,
) -> Array[(Value, Int)] raise @failure.Failure {
  let start = if vertical { source.top } else { source.left }
  let end = if vertical { source.bottom } else { source.right }
  let seeds : Array[(Value, Int)] = []
  let suffixes : Array[(String?, Double, Int)?] = []
  let separators : Array[Bool] = []
  for offset in 0..<(end - start + 1) {
    let axis = if forward { start + offset } else { end - offset }
    let address : Address = if vertical {
      { row: axis, column: lane, }
    } else {
      { row: lane, column: axis, }
    }
    let cell = self.cells.get(address.name())
    let formula = cell.bind(cell => cell.formula)
    guard automatic || formula is None else {
      @failure.reject(
        "invalid-operation", "Text series requires literal text seeds",
      )
    }
    let value = cell.map(cell => cell.value).unwrap_or(Blank)
    let suffix = if formula is Some(_) {
      None
    } else {
      match value {
        Text(text) =>
          series_text_suffix(text).map(suffix => {
            (Some(suffix.0), suffix.1, suffix.2)
          })
        Number(number) =>
          if automatic {
            Some((None, number, 0))
          } else {
            @failure.reject(
              "invalid-operation", "Text series requires text seeds or blanks",
            )
          }
        Blank => None
        _ =>
          if automatic {
            None
          } else {
            @failure.reject(
              "invalid-operation", "Text series requires text seeds or blanks",
            )
          }
      }
    }
    suffixes.push(suffix)
    seeds.push((value, self.style_at(address)))
    separators.push(formula is Some(_) || (value != Blank && value != Text("")))
  }
  let slots : Array[Int?] = Array::make(seeds.length(), None)
  let plans : Array[SeriesPattern] = []
  let mut indices : Array[Int] = []
  for offset, suffix in suffixes {
    match suffix {
      Some((head, _, _)) => {
        if !indices.is_empty() && suffixes[indices[0]].unwrap().0 != head {
          series_pattern_group(
            indices,
            suffixes,
            slots,
            plans,
            forward,
            seeds.length() == 1,
          )
          indices = []
        }
        indices.push(offset)
      }
      None =>
        if separators[offset] {
          series_pattern_group(
            indices,
            suffixes,
            slots,
            plans,
            forward,
            seeds.length() == 1,
          )
          indices = []
        }
    }
  }
  series_pattern_group(
    indices,
    suffixes,
    slots,
    plans,
    forward,
    seeds.length() == 1,
  )
  let values : Array[(Value, Int)] = Array::make(last - first + 1, (Blank, 0))
  let mut units = 0
  for offset in 0..<(last - first + 1) {
    let slot = offset % seeds.length()
    let (original, style) = seeds[slot]
    let value = if offset < seeds.length() {
      original
    } else {
      match slots[slot] {
        Some(plan) => plans[plan].next()
        None => original
      }
    }
    units += value.display().length()
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Text series exceeds source budget")
    }
    let position = if forward { offset } else { values.length() - offset - 1 }
    values[position] = (value, style)
  }
  values
}
