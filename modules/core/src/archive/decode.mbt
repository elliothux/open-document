///|
const EntryChunkBytes : Int32 = 256 * 1024

///|
priv struct EntryInflater {
  inflater : @flate.Inflater
  scratch : FixedArray[Byte]
  mut written : Int32
}

///|
fn EntryInflater::new(decoded : Int32) -> EntryInflater {
  {
    inflater: @flate.Inflater(),
    scratch: FixedArray::make(decoded.min(EntryChunkBytes).max(1), b'\x00'),
    written: 0,
  }
}

///|
fn EntryInflater::consume(
  self : EntryInflater,
  input : BytesView,
  final_chunk : Bool,
  entry : Entry,
  ceiling : Int32,
  name : String,
  write : (FixedArray[Byte], Int32, Int32) -> Unit,
) -> Bool raise @failure.Failure {
  for consumed = 0 {
    let status = self.inflater.step_into(
      input[consumed:],
      self.scratch,
      end=final_chunk,
    ) catch {
      @flate.InflateError(_, message) =>
        @failure.reject("malformed-package", message, part=name)
    }
    let produced = self.inflater.last_produced()
    guard produced <= ceiling - self.written else {
      @failure.reject(
        "limit-exceeded",
        "Entry decode budget exceeded",
        part=name,
      )
    }
    guard produced <= entry.decoded - self.written else {
      @failure.reject(
        "malformed-package",
        "Entry size or CRC mismatch",
        part=name,
      )
    }
    write(self.scratch, self.written, produced)
    self.written += produced
    match status {
      @flate.Done => {
        guard self.written == entry.decoded else {
          @failure.reject(
            "malformed-package",
            "Entry size or CRC mismatch",
            part=name,
          )
        }
        return true
      }
      @flate.NeedMoreInput => return false
      @flate.NeedMoreOutput => continue consumed + self.inflater.last_consumed()
    }
  }
}

///|
fn Source::decode_entry(
  self : Source,
  entry : Entry,
  ceiling : Int32,
  name : String,
) -> Bytes raise @failure.Failure {
  if entry.compression == 0 {
    if entry.decoded <= EntryChunkBytes {
      return self.read(entry.payload, entry.decoded).to_owned()
    }
    let output = FixedArray::make(entry.decoded, b'\x00')
    for offset = 0; offset < entry.decoded; {
      let length = (entry.decoded - offset).min(EntryChunkBytes)
      output.blit_from_bytesview(
        offset,
        self.read(entry.payload + offset, length),
      )
      continue offset + length
    }
    return Bytes::from_array(output)
  }
  let output = FixedArray::make(entry.decoded, b'\x00')
  let inflater = EntryInflater::new(entry.decoded)
  for offset = 0 {
    let length = (entry.compressed - offset).min(EntryChunkBytes)
    let input = self.read(entry.payload + offset, length)
    let final_chunk = offset + length == entry.compressed
    if inflater.consume(input, final_chunk, entry, ceiling, name, (
        scratch,
        written,
        produced,
      ) => scratch.blit_to(output, len=produced, dst_offset=written)) {
      return Bytes::from_array(output)
    }
    continue offset + length
  }
}

///|
priv struct EntryVerifier {
  crc : @checksum.Crc32
  inflater : EntryInflater?
  mut offset : Int32
}

///|
fn Writer::verify(
  self : Writer,
  checkpoint : () -> Unit,
) -> Unit raise @failure.Failure {
  let archive = self.archive
  while self.verify_index < self.originals.length() {
    let name = self.originals[self.verify_index]
    let entry = archive.index[name]
    let ceiling = archive.budget.entry_bytes.min(
      archive.budget.total_bytes - self.verified,
    )
    guard entry.decoded <= ceiling else {
      @failure.reject(
        "limit-exceeded",
        "Entry or cumulative decode budget exceeded",
        part=name,
      )
    }
    let verifier = self.verifier.unwrap_or_else(() => {
      let verifier = {
        crc: @checksum.Crc32(),
        inflater: if entry.compression == 0 {
          None
        } else {
          Some(EntryInflater::new(entry.decoded))
        },
        offset: 0,
      }
      self.verifier = Some(verifier)
      verifier
    })
    verifier.finish(archive.source, entry, ceiling, name, checkpoint)
    self.verified += entry.decoded
    self.verify_index += 1
    self.verifier = None
  }
}

///|
fn EntryVerifier::finish(
  self : EntryVerifier,
  source : Source,
  entry : Entry,
  ceiling : Int32,
  name : String,
  checkpoint : () -> Unit,
) -> Unit raise @failure.Failure {
  for ;; {
    let length = (entry.compressed - self.offset).min(EntryChunkBytes)
    let input = source.read(entry.payload + self.offset, length)
    let final_chunk = self.offset + length == entry.compressed
    let done = match self.inflater {
      Some(inflater) =>
        inflater.consume(input, final_chunk, entry, ceiling, name, (
          scratch,
          _,
          produced,
        ) => self.crc.update(Bytes::from_array(scratch[:produced])))
      None => {
        self.crc.update(input)
        final_chunk
      }
    }
    self.offset += length
    checkpoint()
    if done {
      break
    }
  }
  guard self.crc.finish() == entry.crc else {
    @failure.reject(
      "malformed-package",
      "Entry size or CRC mismatch",
      part=name,
    )
  }
}
