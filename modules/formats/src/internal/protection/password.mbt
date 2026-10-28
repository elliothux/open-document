///|
pub fn password(password : String) -> Unit raise @failure.Failure {
  guard password.length() <= 255 && @xml.valid_text(password) else {
    @failure.reject(
      "invalid-operation", "Protection passwords require at most 255 valid UTF-16 units",
    )
  }
}

///|
pub fn hash(password : String, salt : Bytes, count : Int32) -> Bytes {
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
pub fn matches(
  password : String,
  salt : Bytes,
  count : Int32,
  expected : Bytes,
) -> Bool {
  if expected.length() != 64 {
    return false
  }
  let actual = hash(password, salt, count)
  let mut difference = 0
  for index in 0..<64 {
    difference = difference |
      (actual[index].to_int() ^ expected[index].to_int())
  }
  difference == 0
}
