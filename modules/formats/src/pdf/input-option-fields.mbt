///|
fn choice_options(
  value : @syntax.PdfObject,
) -> Array[(String, String)] raise @failure.Failure {
  guard value is PdfArray(options) &&
    !options.is_empty() &&
    options.length() <= 4096 else {
    @failure.reject(
      "protected-content", "Choice field requires a bounded option list",
    )
  }
  let result : Array[(String, String)] = []
  let mut units = 0
  for option in options {
    let (value, label) = match option {
      PdfString(_) => {
        let text = pdf_text_string(option)
        (text, text)
      }
      PdfArray([value, label]) =>
        (pdf_text_string(value), pdf_text_string(label))
      _ => @failure.reject("protected-content", "Unsupported choice option")
    }
    check_pdf_text(value)
    check_pdf_text(label)
    guard !value.is_empty() &&
      !result.any(option => option.0 == value) &&
      value.length() + label.length() <= 1048576 - units else {
      @failure.reject(
        "protected-content", "Choice options are duplicate, empty or excessive",
      )
    }
    units += value.length() + label.length()
    result.push((value, label))
  }
  result
}

///|
fn PdfTransaction::fill_option_field(
  self : PdfTransaction,
  field : FormField,
  value : Json,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Unit raise {
  if field.kind == "list" {
    return self.fill_list_field(field, value, supplied, profile)
  }
  guard value is String(chosen) &&
    (chosen.is_empty() || field.options.any(option => option.0 == chosen)) else {
    @failure.reject("invalid-operation", "Choose an actual PDF export value")
  }
  let flags = field.attributes.get("Ff").map(integer).unwrap_or(0)
  guard field.kind != "radio" || !chosen.is_empty() || (flags & 16384) == 0 else {
    @failure.reject(
      "invalid-operation", "This field requires a selected option",
    )
  }
  if field.kind == "radio" {
    self.objects[field.number] = self
      .object(field.number)
      .with_entry(
        pdf_name("V"),
        tag(if chosen.is_empty() { "Off" } else { chosen }),
      )
    for (number, _) in field.widgets {
      let state = field.exportStates.get(number).unwrap_or("")
      guard !state.is_empty() else {
        @failure.reject(
          "protected-content", "Radio widget export state is unavailable",
        )
      }
      self.objects[number] = self
        .object(number)
        .with_entry(
          pdf_name("AS"),
          tag(if state == chosen { state } else { "Off" }),
        )
    }
  } else {
    let selected = field.options.filter(option => option.0 == chosen)
    let text = if selected.is_empty() { "" } else { selected[0].1 }
    for (number, page) in field.widgets {
      let appearance = field_appearance(
        self,
        field,
        number,
        self.session.page(page),
        text,
        supplied,
        profile,
      )
      self.objects[number] = self
        .object(number)
        .with_entry(pdf_name("AP"), dict([("N", appearance)]))
    }
    let indices : Array[@syntax.PdfObject] = []
    for index, option in field.options {
      if option.0 == chosen {
        indices.push(@syntax.PdfInteger(index))
      }
    }
    self.objects[field.number] = self
      .object(field.number)
      .with_entry(pdf_name("V"), pdf_string(chosen))
      .with_entry(pdf_name("I"), @syntax.PdfArray(indices))
  }
}

///|
fn PdfTransaction::fill_list_field(
  self : PdfTransaction,
  field : FormField,
  value : Json,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Unit raise {
  guard value is Array(values) && values.length() <= field.options.length() else {
    @failure.reject(
      "invalid-operation", "List field requires bounded export values",
    )
  }
  let selected = values.map(value => {
    guard value is String(text) else {
      @failure.reject("invalid-operation", "List values must be strings")
    }
    text
  })
  let flags = field.attributes.get("Ff").map(integer).unwrap_or(0)
  let seen : Map[String, Bool] = Map([])
  for item in selected {
    guard !seen.contains(item) && field.options.any(option => option.0 == item) else {
      @failure.reject("invalid-operation", "Choose distinct list export values")
    }
    seen[item] = true
  }
  guard (flags & 2097152) != 0 || selected.length() <= 1 else {
    @failure.reject(
      "invalid-operation", "List selection violates the field flags",
    )
  }
  let updated = { ..field, value, }
  for (number, page) in field.widgets {
    let appearance = field_appearance(
      self,
      updated,
      number,
      self.session.page(page),
      "",
      supplied,
      profile,
    )
    self.objects[number] = self
      .object(number)
      .with_entry(pdf_name("AP"), dict([("N", appearance)]))
  }
  let indices : Array[@syntax.PdfObject] = []
  let exports : Array[@syntax.PdfObject] = []
  for index, option in field.options {
    if seen.contains(option.0) {
      indices.push(@syntax.PdfInteger(index))
      exports.push(pdf_string(option.0))
    }
  }
  self.objects[field.number] = self
    .object(field.number)
    .with_entry(
      pdf_name("V"),
      if exports.length() == 1 {
        exports[0]
      } else {
        @syntax.PdfArray(exports)
      },
    )
    .with_entry(pdf_name("I"), @syntax.PdfArray(indices))
}
