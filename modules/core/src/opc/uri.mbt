///|
fn hex(ch : UInt16) -> Int {
  if ch >= '0' && ch <= '9' {
    ch.to_int() - 48
  } else if ch >= 'A' && ch <= 'F' {
    ch.to_int() - 55
  } else if ch >= 'a' && ch <= 'f' {
    ch.to_int() - 87
  } else {
    -1
  }
}

///|
pub fn part_name(name : String) -> Unit raise @failure.Failure {
  guard !name.is_empty() && !name.has_prefix("/") && !name.has_suffix("/") else {
    @failure.reject("malformed-opc", "Invalid part name", part=name)
  }
  for segment in name.split("/") {
    guard !segment.is_empty() &&
      segment != "." &&
      segment != ".." &&
      !segment.has_suffix(".") else {
      @failure.reject("malformed-opc", "Invalid part segment", part=name)
    }
  }
  let decoded : Array[Byte] = []
  for i = 0; i < name.length(); {
    let ch = name[i]
    if ch == '%' {
      guard name.length() - i >= 3 &&
        hex(name[i + 1]) >= 0 &&
        hex(name[i + 2]) >= 0 else {
        @failure.reject(
          "malformed-opc",
          "Invalid percent escape",
          part=name,
          offset=i,
        )
      }
      let byte = hex(name[i + 1]) * 16 + hex(name[i + 2])
      guard !(byte == 47 ||
        byte == 92 ||
        byte == 46 ||
        byte == 45 ||
        byte == 95 ||
        byte == 126 ||
        (byte >= 48 && byte <= 57) ||
        (byte >= 65 && byte <= 90) ||
        (byte >= 97 && byte <= 122)) else {
        @failure.reject(
          "malformed-opc",
          "Noncanonical or escaped path separator",
          part=name,
          offset=i,
        )
      }
      decoded.push(byte.to_byte())
      continue i + 3
    }
    guard (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      "/!$&'()+,-.;=@_~".contains(name[i:i + 1]) else {
      @failure.reject(
        "malformed-opc",
        "Invalid part URI character",
        part=name,
        offset=i,
      )
    }
    decoded.push(ch.to_int().to_byte())
    continue i + 1
  }
  ignore(
    @utf8.decode(Bytes::from_array(decoded)) catch {
      _ => @failure.reject("malformed-opc", "Invalid UTF-8 part URI", part=name)
    },
  )
}

///|
pub fn resolve_target(
  owner : String,
  target : String,
) -> String raise @failure.Failure {
  guard !target.is_empty() &&
    !target.contains(":") &&
    !target.contains("?") &&
    !target.contains("#") &&
    !target.has_prefix("//") else {
    @failure.reject(
      "malformed-opc",
      "Invalid internal relationship target",
      part=owner,
    )
  }
  let segments : Array[String] = []
  if !target.has_prefix("/") && !owner.is_empty() {
    let parent = owner.split("/").map(s => s.to_owned()).collect()
    ignore(parent.pop())
    segments.append(parent)
  }
  let value = if target.has_prefix("/") {
    target[1:].to_owned()
  } else {
    target
  }
  for segment in value.split("/") {
    if segment == ".." {
      guard segments.pop() is Some(_) else {
        @failure.reject(
          "malformed-opc",
          "Relationship escapes package",
          part=owner,
        )
      }
    } else if segment != "." {
      segments.push(segment.to_owned())
    }
  }
  let resolved = segments.join("/")
  part_name(resolved)
  resolved
}
