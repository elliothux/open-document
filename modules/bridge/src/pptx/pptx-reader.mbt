///|
priv struct RangeInput {
  size : Int32
  budget : @archive.Budget
  date_time : String?
  ranges : @common.RangeInput
  mut reader : @archive.Reader?
  mut archive : @archive.Package?
  mut opc : @opc.Package?
  mut presentation : @model.PresentationReader?
  mut session : @model.Session?
  mut writer : (@model.PresentationWriter, Int32)?
}

///|
fn RangeInput::new(
  size : Int32,
  budget : @archive.Budget,
  date_time : String?,
) -> RangeInput {
  {
    size,
    budget,
    date_time,
    ranges: @common.RangeInput::new(),
    reader: None,
    archive: None,
    opc: None,
    presentation: None,
    session: None,
    writer: None,
  }
}

///|
fn RangeInput::close(self : RangeInput) -> Unit {
  if self.session is Some(session) {
    session.close()
  } else if self.opc is Some(opc) {
    opc.close()
  } else if self.archive is Some(archive) {
    archive.close()
  }
  self.reader = None
  self.archive = None
  self.opc = None
  self.presentation = None
  self.session = None
  self.cancel()
}

///|
fn RangeInput::cancel(self : RangeInput) -> Unit {
  self.writer = None
  self.ranges.clear()
}

///|
fn RangeInput::save(
  self : RangeInput,
  session : @model.Session,
  revision : Int32,
) -> Bytes raise @failure.Failure {
  let writer = match self.writer {
    Some((writer, pending_revision)) => {
      guard pending_revision == revision else {
        @failure.reject("invalid-operation", "A PPTX save is in progress")
      }
      writer
    }
    None => {
      let writer = session.start_save(revision)
      self.writer = Some((writer, revision))
      self.ranges.clear()
      writer
    }
  }
  let bytes = writer.finish(() => self.ranges.clear())
  self.writer = None
  bytes
}

///|
#derive(@json.FromJson)
priv struct PptxReaderRequest {
  size : @common.RequestInt
}

///|
fn Context::start_reader(
  self : Context,
  input : Json,
) -> Json raise @failure.Failure {
  let command = pptx_open_request(self, input)
  let source : PptxReaderRequest = @common.request(input)
  self.ranged = Some(
    RangeInput::new(source.size.value, command.budget.value, command.dateTime),
  )
  Json::null()
}

///|
fn Context::open_reader(self : Context) -> Json raise @failure.Failure {
  guard self.pptx is None && self.ranged is Some(ranged) else {
    @failure.reject("invalid-operation", "PPTX source reader is unavailable")
  }
  let result = try {
    let session = ranged.session.unwrap_or_else(() => {
      let session = ranged.open()
      ranged.session = Some(session)
      ranged.opc = None
      ranged.presentation = None
      ranged.ranges.clear()
      session
    })
    session.query()
  } catch {
    @failure.Failure(..) as error => {
      ranged.ranges.require_ranges()
      raise error
    }
  }
  ranged.ranges.require_ranges()
  self.pptx = ranged.session
  ranged.session = None
  ranged.ranges.clear()
  result
}

///|
fn RangeInput::open(self : RangeInput) -> @model.Session raise @failure.Failure {
  let opc = if self.opc is Some(opc) {
    opc
  } else {
    let archive = if self.archive is Some(archive) {
      archive
    } else {
      let reader = self.reader.unwrap_or_else(() => {
        let reader = @archive.Reader::open(
          self.size,
          (offset, length) => self.ranges.read(offset, length),
          self.budget,
        )
        self.reader = Some(reader)
        reader
      })
      let archive = reader.finish()
      self.reader = None
      self.archive = Some(archive)
      self.ranges.clear()
      archive
    }
    let opc = @opc.Package::open_archive(archive, self.budget)
    self.archive = None
    self.opc = Some(opc)
    self.ranges.clear()
    opc
  }
  let presentation = self.presentation.unwrap_or_else(() => {
    let presentation = @model.PresentationReader::open(
      opc,
      self.budget,
      date_time?=self.date_time,
    )
    self.presentation = Some(presentation)
    presentation
  })
  presentation.finish(checkpoint=() => {
    self.ranges.require_ranges()
    self.ranges.clear()
  })
}
