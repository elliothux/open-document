///|
fn encryption_u32(data : Bytes, offset : Int32) -> UInt32 {
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

///|
fn encrypted_office_size(
  payload : Bytes,
  maximum : Int32,
) -> Int32 raise @failure.Failure {
  guard payload.length() >= 24 else {
    @failure.reject("malformed-package", "Truncated encrypted Office package")
  }
  let size = encryption_u32(payload, 0)
  let cipher_size = payload.length() - 8
  guard encryption_u32(payload, 4) == 0U &&
    size > 0U &&
    size <= cipher_size.reinterpret_as_uint() &&
    cipher_size % 16 == 0 &&
    cipher_size - size.reinterpret_as_int() < 16 else {
    @failure.reject(
      "malformed-package", "Invalid encrypted Office stream lengths",
    )
  }
  guard maximum >= 0 && size <= maximum.reinterpret_as_uint() else {
    @failure.reject(
      "limit-exceeded", "Decrypted Office package exceeds retained source budget",
    )
  }
  size.reinterpret_as_int()
}

///|
fn required_office_password(
  password : String?,
) -> String raise @failure.Failure {
  guard password is Some(password) else {
    @failure.reject(
      "docx-password-required", "A password is required to open this DOCX",
    )
  }
  guard password.length() <= @protection.PasswordUnits else {
    @failure.reject(
      "invalid-operation", "Office passwords require at most 255 UTF-16 units",
    )
  }
  password
}

///|
fn office_digest_matches(digest : FixedArray[Byte], expected : Bytes) -> Bool {
  guard expected.length() >= digest.length() else { return false }
  let mut difference = 0
  for byte in 0..<digest.length() {
    difference = difference | (digest[byte].to_int() ^ expected[byte].to_int())
  }
  difference == 0
}

///|
fn office_sha1_password_hash(
  password : String,
  salt : BytesView,
  spin : Int32,
) -> FixedArray[Byte] {
  let initial = Buffer()
  initial.write_bytes(salt)
  initial.write_bytes(
    @utf16.encode(password[:], bom=false, endianness=@utf16.Little)[:],
  )
  let mut digest = @crypto.sha1(initial.to_bytes())
  let iteration : FixedArray[Byte] = FixedArray::make(24, 0)
  for index in 0..<spin {
    for byte in 0..<4 {
      iteration[byte] = (index >> (byte * 8)).to_byte()
    }
    for byte in 0..<20 {
      iteration[byte + 4] = digest[byte]
    }
    digest = @crypto.sha1(iteration)
  }
  digest
}

///|
fn standard_encryption_key(
  password : String,
  salt : BytesView,
  size : Int32,
) -> Bytes {
  let digest = office_sha1_password_hash(password, salt, 50000)
  let block_digest = @crypto.sha1(
    FixedArray::makei(24, byte => if byte < 20 { digest[byte] } else { 0 }),
  )
  let padded_hash = fn(pad : Byte) {
    @crypto.sha1(
      FixedArray::makei(64, byte => {
        if byte < 20 {
          block_digest[byte] ^ pad
        } else {
          pad
        }
      }),
    )
  }
  let first = padded_hash(0x36)
  let second = padded_hash(0x5c)
  Bytes::from_array(
    Array::makei(size, byte => {
      if byte < 20 {
        first[byte]
      } else {
        second[byte - 20]
      }
    }),
  )
}

///|
fn decrypt_standard_office(
  info : Bytes,
  payload : Bytes,
  password : String?,
  maximum : Int32,
) -> Bytes raise @failure.Failure {
  guard info.length() >= 12 && payload.length() >= 24 else {
    @failure.reject("malformed-package", "Truncated encrypted Office streams")
  }
  let version = encryption_u32(info, 0)
  guard [0x00020002U, 0x00020003U, 0x00020004U].contains(version) else {
    @failure.reject("unsupported-docx", "Unsupported Office encryption version")
  }
  let header = encryption_u32(info, 8)
  guard info.length() >= 116 &&
    header >= 32U &&
    header <= (info.length() - 84).reinterpret_as_uint() else {
    @failure.reject(
      "malformed-package", "Invalid Office encryption header size",
    )
  }
  let algorithm = encryption_u32(info, 20)
  let key_size = match (algorithm, encryption_u32(info, 28)) {
    (0x660eU, 128U) => 16
    (0x660fU, 192U) => 24
    (0x6610U, 256U) => 32
    _ =>
      @failure.reject(
        "unsupported-docx", "Unsupported Office encryption cipher",
      )
  }
  guard encryption_u32(info, 4) == 0x24U &&
    encryption_u32(info, 12) == 0x24U &&
    encryption_u32(info, 16) == 0U &&
    encryption_u32(info, 24) == 0x8004U else {
    @failure.reject("unsupported-docx", "Unsupported Office encryption options")
  }
  let verifier = 12 + header.reinterpret_as_int()
  guard encryption_u32(info, verifier) == 16U &&
    encryption_u32(info, verifier + 36) == 20U else {
    @failure.reject(
      "malformed-package", "Invalid encrypted Office stream lengths",
    )
  }
  let size = encrypted_office_size(payload, maximum)
  let password = required_office_password(password)
  let key = standard_encryption_key(
    password,
    info[verifier + 4:verifier + 20],
    key_size,
  )
  let decrypt = fn(data : BytesView) raise @failure.Failure {
    @crypto.aes_ecb_decrypt(key[:], data) catch {
      _ =>
        @failure.reject("malformed-package", "Invalid Office encryption block")
    }
  }
  let value = decrypt(info[verifier + 20:verifier + 36])
  let expected = decrypt(info[verifier + 40:verifier + 72])
  guard office_digest_matches(@crypto.sha1(value), expected) else {
    @failure.reject("docx-password-required", "The DOCX password is incorrect")
  }
  decrypt(payload[8:])[:size].to_owned()
}
