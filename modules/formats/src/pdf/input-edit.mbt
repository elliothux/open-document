///|
priv struct PdfTransaction {
  session : PdfSession
  objects : Map[Int32, @syntax.PdfObject]
  mut next : Int32
  mut trailer : @syntax.PdfObject
}

///|
fn PdfSession::transaction(
  self : PdfSession,
  revision : Int32,
) -> PdfTransaction raise @failure.Failure {
  self.check(revision)
  guard self.readOnlyReason.is_empty() else {
    @failure.reject("protected-content", self.readOnlyReason)
  }
  {
    session: self,
    objects: Map([]),
    next: self.nextObject,
    trailer: self.document.trailer_dict().deep_copy(),
  }
}

///|
fn PdfTransaction::object(
  self : PdfTransaction,
  number : Int32,
) -> @syntax.PdfObject {
  self.objects
  .get(number)
  .unwrap_or(self.session.document.lookup_object_or_null(number))
  .deep_copy()
}

///|
fn PdfTransaction::add(
  self : PdfTransaction,
  value : @syntax.PdfObject,
) -> @syntax.PdfObject raise @failure.Failure {
  guard self.next <= self.session.budget.objectNumber &&
    self.session.generations.length() + self.next - self.session.nextObject <
    self.session.budget.objects else {
    @failure.reject("limit-exceeded", "New PDF object exceeds budget")
  }
  let id = self.next
  self.next += 1
  self.objects[id] = value
  @syntax.PdfIndirect(id)
}

///|
fn object_size(
  value : @syntax.PdfObject,
  depth : Int32,
  limit : Int64,
) -> Int64 raise @failure.Failure {
  guard depth < 64 else {
    @failure.reject("limit-exceeded", "PDF object depth exceeds budget")
  }
  let size : Int64 = match value {
    PdfString(bytes) => bytes.length().to_int64() * 4 + 2
    PdfNameObject(name) => name.bytes().length().to_int64() * 3 + 1
    PdfArray(items) => {
      let mut total : Int64 = 2
      for item in items {
        total += object_size(item, depth + 1, limit - total) + 1
      }
      total
    }
    PdfDictionary(entries) => {
      let mut total : Int64 = 4
      for (key, item) in entries {
        total += key.bytes().length().to_int64() * 3 + 2
        total += object_size(item, depth + 1, limit - total) + 1
      }
      total
    }
    PdfStreamObject(stream) => {
      let length = match stream.data {
        StreamGot(bytes) => bytes.length()
        StreamToGet(value) => value.length
      }
      object_size(stream.dictionary, depth + 1, limit) + length.to_int64() + 64
    }
    _ => 64
  }
  guard size <= limit else {
    @failure.reject("limit-exceeded", "PDF object or output exceeds budget")
  }
  size
}

///|
fn document_view(source : @pdflite.PdfDocument) -> @pdflite.PdfDocument {
  let view = @pdflite.pdf_document_empty()
  let (major, minor) = source.version()
  view.set_version(major, minor)
  view.set_root(source.root())
  view.set_trailer_dict(source.trailer_dict())
  for (number, generation, object) in source.parsed_object_entries() {
    view.add_object_given_number(number, object, generation~)
  }
  view
}

///|
fn PdfTransaction::commit(
  self : PdfTransaction,
  page : String,
) -> Json raise @failure.Failure {
  let session = self.session
  if self.objects.is_empty() {
    return session.query()
  }
  pdf_bound(session.budget, () => {
    let changes : Array[ObjectChange] = []
    let mut size : Int64 = 0
    for number, value in self.objects {
      let before = if session.generations.contains(number) {
        Some(session.document.lookup_object_or_null(number))
      } else {
        None
      }
      if before is Some(original) && original == value {
        continue
      }
      size += object_size(value, 0, 8388608 - size)
      if before is Some(original) {
        size += object_size(original, 0, 8388608 - size)
      }
      changes.push({
        number,
        generation: session.generations.get(number).unwrap_or(0),
        before,
        after: value,
      })
    }
    if changes.is_empty() {
      return session.query()
    }
    let view = document_view(session.document)
    let beforeTrailer = session.document.trailer_dict().deep_copy()
    view.set_trailer_dict(self.trailer)
    let numbers = session.generations.copy()
    for change in changes {
      numbers[change.number] = change.generation
      view.add_object_given_number(
        change.number,
        change.after,
        generation=change.generation,
      )
    }
    for change in changes {
      validate_value(numbers, change.after, 0)
    }
    validate_value(numbers, self.trailer, 0)
    let pages = read_pages(view, numbers, session.budget)
    guard pages.any(item => item.id == page) else {
      @failure.reject("invalid-page", "PDF transaction removed the active page")
    }
    let candidate : PdfSession = {
      ..session,
      document: view,
      pages,
      revision: session.revision + 1,
      current: page,
      stateId: session.nextState,
      display: None,
    }
    let result = candidate.query()
    guard result is Object(fields) else {
      @failure.reject("invalid-pdf", "Invalid PDF candidate state")
    }
    // Only the checked candidate containers become visible at this point.
    for change in changes {
      session.document.add_object_given_number(
        change.number,
        change.after,
        generation=change.generation,
      )
      session.generations[change.number] = change.generation
    }
    session.document.sdk_clear_events()
    session.document.set_trailer_dict(self.trailer)
    for entry in session.redo {
      session.historyBytes -= entry.bytes
    }
    session.redo.clear()
    while session.undo.length() >= 100 ||
          session.historyBytes + size.to_int() > 8388608 {
      session.historyBytes -= session.undo.remove(0).bytes
    }
    session.undo.push({
      beforeTrailer,
      afterTrailer: self.trailer,
      changes,
      bytes: size.to_int(),
      beforePage: session.current,
      afterPage: page,
      beforeSelection: session.selection,
      beforeState: session.stateId,
      afterState: session.nextState,
    })
    session.historyBytes += size.to_int()
    session.stateId = session.nextState
    session.nextState += 1
    session.nextObject = self.next
    session.pages = pages
    session.current = page
    session.selection = (0, 0)
    session.revision += 1
    session.invalidate()
    fields["canUndo"] = Json(true)
    fields["canRedo"] = Json(false)
    fields["historyBytes"] = Json(session.historyBytes)
    result
  })
}

///|
pub fn PdfSession::invalidate(self : PdfSession) -> Unit {
  self.textRange = None
  for _, display in self.views {
    display.probe.close()
  }
  self.views.clear()
  self.display = None
}

///|
pub fn PdfSession::undo_edit(
  self : PdfSession,
  revision : Int32,
  redo : Bool,
) -> Json raise @failure.Failure {
  self.check(revision)
  let source = if redo { self.redo } else { self.undo }
  let target = if redo { self.undo } else { self.redo }
  if source.is_empty() {
    return self.query()
  }
  let entry = source[source.length() - 1]
  let view = document_view(self.document)
  let trailer = if redo { entry.afterTrailer } else { entry.beforeTrailer }
  view.set_trailer_dict(trailer)
  let numbers = self.generations.copy()
  for change in entry.changes {
    if redo {
      view.add_object_given_number(
        change.number,
        change.after,
        generation=change.generation,
      )
      numbers[change.number] = change.generation
    } else if change.before is Some(value) {
      view.add_object_given_number(
        change.number,
        value,
        generation=change.generation,
      )
    } else {
      view.remove_object(change.number)
      numbers.remove(change.number)
    }
  }
  let (pages, result) = pdf_bound(self.budget, () => {
    let pages = read_pages(view, numbers, self.budget)
    let candidate : PdfSession = {
      ..self,
      document: view,
      pages,
      revision: self.revision + 1,
      current: if redo {
        entry.afterPage
      } else {
        entry.beforePage
      },
      stateId: if redo {
        entry.afterState
      } else {
        entry.beforeState
      },
      display: None,
    }
    (pages, candidate.query())
  })
  guard result is Object(fields) else {
    @failure.reject("invalid-pdf", "Invalid PDF history state")
  }
  for change in entry.changes {
    if redo {
      self.document.add_object_given_number(
        change.number,
        change.after,
        generation=change.generation,
      )
      self.generations[change.number] = change.generation
    } else if change.before is Some(value) {
      self.document.add_object_given_number(
        change.number,
        value,
        generation=change.generation,
      )
    } else {
      self.document.remove_object(change.number)
      self.generations.remove(change.number)
    }
  }
  ignore(source.pop())
  self.document.set_trailer_dict(trailer)
  self.document.sdk_clear_events()
  target.push(entry)
  self.pages = pages
  self.current = if redo { entry.afterPage } else { entry.beforePage }
  self.selection = if redo { (0, 0) } else { entry.beforeSelection }
  self.stateId = if redo { entry.afterState } else { entry.beforeState }
  self.revision += 1
  self.invalidate()
  fields["canUndo"] = Json(!self.undo.is_empty())
  fields["canRedo"] = Json(!self.redo.is_empty())
  result
}

///|
pub fn PdfSession::save(
  self : PdfSession,
  revision : Int32,
) -> Bytes raise @failure.Failure {
  self.check(revision)
  if self.stateId == 0 {
    return self.original
  }
  guard self.readOnlyReason.is_empty() else {
    @failure.reject("protected-content", self.readOnlyReason)
  }
  pdf_bound(self.budget, () => {
    let document = document_view(self.document)
    document.set_version(1, 7)
    let trailer = document.trailer_dict().deep_copy()
    let mut trailer = trailer
    for
      key in [
        "Prev", "XRefStm", "W", "Index", "Type", "Length", "Filter", "DecodeParms",
      ] {
      trailer = trailer.remove_dict_entry(pdf_name(key))
    }
    document.set_trailer_dict(trailer)
    for (id, generation, value) in document.parsed_object_entries() {
      if raw(value, "Linearized") != @syntax.PdfNull {
        document.add_object_given_number(
          id,
          value.deep_copy().remove_dict_entry(pdf_name("Linearized")),
          generation~,
        )
      }
    }
    let mut estimate : Int64 = 1024 + (self.nextObject.to_int64() + 1) * 20
    for (_, _, value) in document.parsed_object_entries() {
      estimate += object_size(
          value,
          0,
          self.budget.outputBytes.to_int64() - estimate,
        ) +
        128
    }
    guard estimate <= self.budget.outputBytes.to_int64() else {
      @failure.reject("limit-exceeded", "PDF output exceeds budget")
    }
    let bytes = @pdflite.pdf_write_document(document)
    guard bytes.length() <= self.budget.outputBytes else {
      @failure.reject("limit-exceeded", "PDF output exceeds budget")
    }
    bytes
  })
}
