///|
fn protection_password(password : String) -> Unit raise @failure.Failure {
  guard password.length() <= 255 && @xml.valid_text(password) else {
    @failure.reject(
      "invalid-operation", "Protection passwords require at most 255 valid UTF-16 units",
    )
  }
}

///|
fn protection_hash(password : String, salt : Bytes, count : Int) -> Bytes {
  let context = @crypto.SHA512::new()
  context.update(salt)
  context.update(
    @utf16.encode(password[:], bom=false, endianness=@utf16.Little),
  )
  let digest : FixedArray[Byte] = FixedArray::make(64, 0)
  context.finalize_into(digest, offset=0)
  let counter : FixedArray[Byte] = FixedArray::make(4, 0)
  for index in 0..<count {
    for byte in 0..<4 {
      counter[byte] = ((index >> (byte * 8)) & 255).to_byte()
    }
    context.reset()
    context.update(digest)
    context.update(counter)
    context.finalize_into(digest, offset=0)
  }
  Bytes::from_array(Array::makei(64, index => digest[index]))
}

///|
fn protection_legacy_hash(password : String) -> Int {
  let mut value = 0
  for index = password.length() - 1; index >= 0; index = index - 1 {
    value = (((value >> 14) & 1) | ((value << 1) & 32767)) ^
      password[index].to_int()
  }
  (((value >> 14) & 1) | ((value << 1) & 32767)) ^ 0xce4b ^ password.length()
}

///|
fn protection_credentials(
  node : @xml.Node,
  workbook~ : Bool = false,
) -> (Bytes, Bytes, Int)? raise @failure.Failure {
  let modern = if workbook {
    [
      "workbookAlgorithmName", "workbookHashValue", "workbookSaltValue", "workbookSpinCount",
    ]
  } else {
    ["algorithmName", "hashValue", "saltValue", "spinCount"]
  }
  let legacy = if workbook { "workbookPassword" } else { "password" }
  if modern.any(name => node.attribute(name) is Some(_)) {
    guard node.attribute(modern[0]) == Some("SHA-512") &&
      modern.all(name => node.attribute(name) is Some(_)) &&
      node.attribute(legacy) is None else {
      @failure.reject(
        "protected-content", "Unsupported protection password algorithm or mixed credentials",
      )
    }
    guard node.attribute(modern[2]).unwrap().length() <= 128 &&
      node.attribute(modern[1]).unwrap().length() <= 128 else {
      @failure.reject(
        "protected-content", "Protection password credentials exceed bounds",
      )
    }
    let salt = @base64.decode(node.attribute(modern[2]).unwrap()[:]) catch {
      _ =>
        @failure.reject("protected-content", "Invalid protection password salt")
    }
    let hash = @base64.decode(node.attribute(modern[1]).unwrap()[:]) catch {
      _ =>
        @failure.reject("protected-content", "Invalid protection password hash")
    }
    let count = natural(node.attribute(modern[3]).unwrap(), 1000000)
    guard salt.length() >= 1 && salt.length() <= 64 && hash.length() == 64 else {
      @failure.reject(
        "protected-content", "Invalid protection password credentials",
      )
    }
    return Some((salt, hash, count))
  }
  if node.attribute(legacy) is Some(value) {
    guard !value.is_empty() &&
      value.length() <= 4 &&
      value.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject("protected-content", "Invalid legacy protection password")
    }
  }
  None
}

///|
fn check_protection_password(
  node : @xml.Node,
  password : String,
  workbook~ : Bool = false,
) -> Unit raise @failure.Failure {
  let legacy = if workbook { "workbookPassword" } else { "password" }
  let subject = if workbook { "Workbook" } else { "Worksheet" }
  if protection_credentials(node, workbook~) is Some((salt, expected, count)) {
    let actual = protection_hash(password, salt, count)
    let mut difference = 0
    for index in 0..<64 {
      difference = difference |
        (actual[index].to_int() ^ expected[index].to_int())
    }
    guard difference == 0 else {
      @failure.reject("protected-content", subject + " password is incorrect")
    }
  } else if node.attribute(legacy) is Some(value) {
    let expected = @string.parse_int(value, base=16) catch {
      _ =>
        @failure.reject(
          "protected-content", "Invalid legacy protection password",
        )
    }
    guard !password.is_empty() && protection_legacy_hash(password) == expected else {
      @failure.reject("protected-content", subject + " password is incorrect")
    }
  }
}
