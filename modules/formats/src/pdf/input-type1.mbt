///|
priv struct Type1Reader {
  bytes : Bytes
  mut offset : Int32
}

///|
fn type1_space(byte : Byte) -> Bool {
  [0, 9, 10, 12, 13, 32].contains(byte.to_int())
}

///|
fn Type1Reader::token(self : Type1Reader) -> String? raise {
  let bytes = self.bytes
  while self.offset < bytes.length() {
    @pdfcore.sdk_check(1)
    let byte = bytes[self.offset]
    if type1_space(byte) {
      self.offset += 1
    } else if byte == b'%' {
      while self.offset < bytes.length() &&
            ![10, 13].contains(bytes[self.offset].to_int()) {
        @pdfcore.sdk_check(1)
        self.offset += 1
      }
    } else {
      break
    }
  }
  if self.offset == bytes.length() {
    return None
  }
  let start = self.offset
  self.offset += 1
  if bytes[start] == b'(' {
    for depth = 1; depth > 0; {
      guard depth <= 64 else {
        @failure.reject(
          "limit-exceeded", "Type 1 string nesting exceeds budget",
        )
      }
      guard self.offset < bytes.length() else {
        @failure.reject("invalid-pdf", "Truncated Type 1 string")
      }
      @pdfcore.sdk_check(1)
      let byte = bytes[self.offset]
      self.offset += 1
      if byte == b'\\' {
        guard self.offset < bytes.length() else {
          @failure.reject("invalid-pdf", "Truncated Type 1 escape")
        }
        self.offset += 1
        continue depth
      }
      continue if byte == b'(' {
          depth + 1
        } else if byte == b')' {
          depth - 1
        } else {
          depth
        }
    }
    return Some("()")
  }
  if ![b'[', b']', b'{', b'}', b'<', b'>'].contains(bytes[start]) {
    while self.offset < bytes.length() &&
          !type1_space(bytes[self.offset]) &&
          ![b'/', b'[', b']', b'{', b'}', b'(', b')', b'<', b'>', b'%'].contains(
            bytes[self.offset],
          ) {
      @pdfcore.sdk_check(1)
      self.offset += 1
    }
  }
  guard self.offset - start <= 1024 else {
    @failure.reject("limit-exceeded", "Type 1 token exceeds budget")
  }
  Some(@utf8.decode_lossy(bytes[start:self.offset].to_owned()))
}

///|
fn Type1Reader::required(self : Type1Reader) -> String raise {
  guard self.token() is Some(token) else {
    @failure.reject("invalid-pdf", "Truncated Type 1 dictionary")
  }
  token
}

///|
fn Type1Reader::integer(self : Type1Reader) -> Int32 raise {
  let value = @string.parse_int(self.required()) catch {
    _ => @failure.reject("invalid-pdf", "Invalid Type 1 integer")
  }
  value
}

///|
fn Type1Reader::binary(self : Type1Reader, length : Int32) -> Bytes raise {
  guard ["RD", "-|"].contains(self.required()) &&
    length >= 0 &&
    length <= 1048576 &&
    self.offset < self.bytes.length() &&
    type1_space(self.bytes[self.offset]) else {
    @failure.reject("invalid-pdf", "Invalid Type 1 binary string")
  }
  if self.bytes[self.offset] == b'\r' &&
    self.offset + 1 < self.bytes.length() &&
    self.bytes[self.offset + 1] == b'\n' {
    self.offset += 1
  }
  self.offset += 1
  guard length <= self.bytes.length() - self.offset else {
    @failure.reject("invalid-pdf", "Truncated Type 1 binary string")
  }
  @pdfcore.sdk_decoded(length)
  let result = self.bytes[self.offset:self.offset + length].to_owned()
  self.offset += length
  result
}

///|
fn type1_decrypt(bytes : Bytes, key : Int32, skip : Int32) -> Bytes raise {
  guard skip >= 0 && skip <= bytes.length() else {
    @failure.reject("invalid-pdf", "Truncated Type 1 encrypted string")
  }
  @pdfcore.sdk_decoded(bytes.length() - skip)
  @pdfcore.sdk_check(bytes.length())
  let output : Array[Byte] = []
  let mut key = key
  for i, byte in bytes {
    let value = byte.to_int()
    if i >= skip {
      output.push((value ^ (key >> 8)).to_byte())
    }
    key = ((value + key) * 52845 + 22719) & 65535
  }
  Bytes::from_array(output)
}

///|
fn embedded_type1(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> (@pdflite.SdkType1Font, Array[(Int32, @pdfcore.PdfName)])? raise {
  if !is_name(get(document, object, "Subtype"), "Type1") {
    return None
  }
  let stream = get(
    document,
    get(document, object, "FontDescriptor"),
    "FontFile",
  )
  if stream == @syntax.PdfNull {
    return None
  }
  let bytes = stream_bytes(document, stream)
  let clear_length = integer(get(document, stream, "Length1"))
  let private_length = integer(get(document, stream, "Length2"))
  guard bytes.length() <= 33554432 &&
    clear_length > 0 &&
    clear_length <= bytes.length() &&
    private_length >= 4 &&
    private_length <= bytes.length() - clear_length else {
    @failure.reject("invalid-pdf", "Invalid Type 1 font section lengths")
  }
  let header : Type1Reader = {
    bytes: bytes[:clear_length].to_owned(),
    offset: 0,
  }
  let transform = [0.001, 0.0, 0.0, 0.001, 0.0, 0.0]
  let encoding : Map[Int32, @pdfcore.PdfName] = Map([])
  let mut in_encoding = false
  let mut level = 0
  while header.token() is Some(token) {
    if token == "{" {
      guard level < 64 else {
        @failure.reject(
          "limit-exceeded", "Type 1 procedure nesting exceeds budget",
        )
      }
      level += 1
      continue
    }
    if token == "}" {
      guard level > 0 else {
        @failure.reject("invalid-pdf", "Unbalanced Type 1 procedure")
      }
      level -= 1
      continue
    }
    if level != 0 {
      continue
    }
    match token {
      "/FontType" => {
        guard header.integer() == 1 else {
          @failure.reject("unsupported-pdf", "Type 1 font requires FontType 1")
        }
      }
      "/PaintType" | "/WMode" => {
        guard header.integer() == 0 else {
          @failure.reject(
            "unsupported-pdf", "Type 1 stroked or vertical font is unsupported",
          )
        }
      }
      "/Blend" | "/WeightVector" | "/DesignVector" =>
        @failure.reject(
          "unsupported-pdf", "Multiple master Type 1 fonts are unsupported",
        )
      "/FontMatrix" => {
        guard header.required() == "[" else {
          @failure.reject("invalid-pdf", "Invalid Type 1 FontMatrix")
        }
        for i in 0..<6 {
          transform[i] = @string.parse_double(header.required()) catch {
            _ =>
              @failure.reject(
                "invalid-pdf", "Invalid Type 1 FontMatrix component",
              )
          }
        }
        guard header.required() == "]" else {
          @failure.reject("invalid-pdf", "Invalid Type 1 FontMatrix length")
        }
      }
      "/Encoding" => {
        in_encoding = true
        encoding.clear()
        match header.required() {
          "StandardEncoding" =>
            for (code, name) in @pdflite.PdfStandardEncoding.table() {
              encoding[code] = name
            }
          "256" => {
            guard header.required() == "array" else {
              @failure.reject(
                "unsupported-pdf", "Type 1 encoding requires a literal array",
              )
            }
          }
          _ =>
            @failure.reject(
              "unsupported-pdf", "Type 1 encoding program is unsupported",
            )
        }
      }
      "dup" if in_encoding => {
        let code = header.integer()
        let name = header.required()
        guard code >= 0 &&
          code <= 255 &&
          name.has_prefix("/") &&
          header.required() == "put" else {
          @failure.reject("invalid-pdf", "Invalid Type 1 encoded glyph")
        }
        encoding[code] = @pdfcore.pdf_name_of_bytes(@utf8.encode(name))
      }
      "def" => in_encoding = false
      _ => ()
    }
  }
  let encrypted = bytes[clear_length:clear_length + private_length].to_owned()
  // shortcut: FontFile requires binary eexec; add hex containers when a source requires them.
  guard !encrypted[:4]
    .iter()
    .all(byte => @syntax.pdf_hex_value(byte.to_int()) is Some(_)) else {
    @failure.reject(
      "unsupported-pdf", "Hexadecimal Type 1 eexec is unsupported",
    )
  }
  let reader : Type1Reader = {
    bytes: type1_decrypt(encrypted, 55665, 4),
    offset: 0,
  }
  let subrs : Map[Int32, Bytes] = Map([])
  let glyphs : Map[String, Bytes] = Map([])
  let mut len_iv = 4
  let mut subr_count = 0
  let mut glyph_count = 0
  let mut section = ""
  let mut level = 0
  while reader.token() is Some(token) {
    if token == "{" {
      guard level < 64 else {
        @failure.reject(
          "limit-exceeded", "Type 1 procedure nesting exceeds budget",
        )
      }
      level += 1
      continue
    }
    if token == "}" {
      guard level > 0 else {
        @failure.reject("invalid-pdf", "Unbalanced Type 1 procedure")
      }
      level -= 1
      continue
    }
    if level != 0 {
      continue
    }
    match token {
      name if section == "/CharStrings" && name.has_prefix("/") => {
        let length = reader.integer()
        let name = name[1:].to_owned()
        guard !name.is_empty() &&
          name.length() <= 256 &&
          !glyphs.contains(name) &&
          glyphs.length() < glyph_count else {
          @failure.reject("invalid-pdf", "Invalid Type 1 glyph dictionary")
        }
        glyphs[name] = reader.binary(length)
      }
      "/lenIV" => {
        len_iv = reader.integer()
        guard len_iv >= -1 && len_iv <= 1048576 else {
          @failure.reject("invalid-pdf", "Invalid Type 1 lenIV")
        }
      }
      "/Subrs" | "/CharStrings" => {
        let count = reader.integer()
        guard count >= 0 && count <= 65535 else {
          @failure.reject(
            "limit-exceeded", "Type 1 program count exceeds budget",
          )
        }
        section = token
        if token == "/Subrs" {
          subr_count = count
        } else {
          glyph_count = count
        }
      }
      "dup" if section == "/Subrs" => {
        let index = reader.integer()
        let length = reader.integer()
        guard index >= 0 && index < subr_count && !subrs.contains(index) else {
          @failure.reject("invalid-pdf", "Invalid Type 1 subroutine index")
        }
        subrs[index] = reader.binary(length)
      }
      "end" if section == "/CharStrings" => break
      _ => ()
    }
  }
  guard !glyphs.is_empty() else {
    @failure.reject("invalid-pdf", "Missing Type 1 CharStrings")
  }
  if len_iv >= 0 {
    for (name, bytes) in glyphs {
      glyphs[name] = type1_decrypt(bytes, 4330, len_iv)
    }
    for (index, bytes) in subrs {
      subrs[index] = type1_decrypt(bytes, 4330, len_iv)
    }
  }
  Some(
    (@pdflite.SdkType1Font::new(glyphs, subrs, transform), encoding.to_array()),
  )
}
