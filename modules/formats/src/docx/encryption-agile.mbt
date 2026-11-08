///|
fn agile_field(
  node : @xml.Node,
  name : String,
  sizes : Array[Int32],
) -> Bytes raise @failure.Failure {
  guard node.attribute(name) is Some(encoded) else {
    @failure.reject(
      "malformed-package",
      "Missing Agile encryption field",
      part=name,
    )
  }
  let decoded = @base64.decode(encoded[:]) catch {
    _ =>
      @failure.reject(
        "malformed-package",
        "Invalid Agile base64 field",
        part=name,
      )
  }
  guard sizes.contains(decoded.length()) else {
    @failure.reject(
      "malformed-package",
      "Invalid Agile field length",
      part=name,
    )
  }
  decoded
}

///|
fn agile_key_size(node : @xml.Node) -> Int32 raise @failure.Failure {
  guard node.attribute("cipherAlgorithm") == Some("AES") &&
    node.attribute("cipherChaining") == Some("ChainingModeCBC") &&
    node.attribute("blockSize") == Some("16") &&
    node.attribute("saltSize") == Some("16") else {
    @failure.reject(
      "unsupported-docx", "Unsupported Agile encryption parameters",
    )
  }
  match
    (
      node.attribute("hashAlgorithm"),
      node.attribute("hashSize"),
      node.attribute("keyBits"),
    ) {
    (Some("SHA1" | "SHA-1"), Some("20"), Some("128")) => 16
    (Some("SHA512"), Some("64"), Some("256")) => 32
    _ =>
      @failure.reject(
        "unsupported-docx", "Unsupported Agile encryption parameters",
      )
  }
}

///|
fn agile_sha512_password_hash(
  password : String,
  salt : Bytes,
  spin : Int32,
) -> FixedArray[Byte] {
  let hash = @crypto.SHA512::new()
  hash.update(salt)
  hash.update(@utf16.encode(password[:], bom=false, endianness=@utf16.Little))
  let digest : FixedArray[Byte] = FixedArray::make(64, 0)
  hash.finalize_into(digest, offset=0)
  let counter : FixedArray[Byte] = FixedArray::make(4, 0)
  for index in 0..<spin {
    for byte in 0..<4 {
      counter[byte] = (index >> (byte * 8)).to_byte()
    }
    hash.reset()
    hash.update(counter)
    hash.update(digest)
    hash.finalize_into(digest, offset=0)
  }
  digest
}

///|
fn agile_cbc(
  key : BytesView,
  iv : BytesView,
  data : BytesView,
) -> Bytes raise @failure.Failure {
  @crypto.aes_cbc_decrypt(key, iv, data) catch {
    _ => @failure.reject("malformed-package", "Invalid Agile encryption block")
  }
}

///|
fn agile_digest(sha1 : Bool, input : Bytes) -> FixedArray[Byte] {
  if sha1 {
    @crypto.sha1(input)
  } else {
    @crypto.sha512(input)
  }
}

///|
fn agile_derive(
  sha1 : Bool,
  prefix : Bytes,
  block : Bytes,
  size : Int32,
) -> Bytes {
  let digest = agile_digest(sha1, prefix + block)
  Bytes::from_array(digest[:size])
}

///|
fn agile_hmac(sha1 : Bool, key : Bytes, payload : Bytes) -> FixedArray[Byte] {
  if !sha1 {
    return @crypto.hmac(@crypto.SHA512::new(), key[:], payload[:])
  }
  // Agile's SHA-1 HMAC key is already bounded below one hash block.
  let pad = fn(value : Byte) {
    Bytes::from_array(
      Array::makei(64, index => key.get(index).unwrap_or(0) ^ value),
    )
  }
  let inner = @crypto.sha1(pad(0x36) + payload)
  @crypto.sha1(pad(0x5c) + Bytes::from_array(inner[:]))
}

///|
fn decrypt_agile_office(
  info : Bytes,
  payload : Bytes,
  password : String?,
  maximum : Int32,
  budget : @archive.Budget,
) -> Bytes raise @failure.Failure {
  guard info.length() > 8 && encryption_u32(info, 4) == 0x40U else {
    @failure.reject("malformed-package", "Invalid Agile encryption header")
  }
  let size = encrypted_office_size(payload, maximum)
  let xml_limit = budget.entry_bytes.min(16384)
  guard info.length() - 8 <= xml_limit else {
    @failure.reject("limit-exceeded", "Agile encryption XML budget exceeded")
  }
  let nodes = @xml.Document::parse(
    info[8:].to_owned(),
    "EncryptionInfo",
    budget.xml_depth.min(8),
    xml_limit,
  ).nodes()
  let uri = "http://schemas.microsoft.com/office/2006/encryption"
  let password_uri = "http://schemas.microsoft.com/office/2006/keyEncryptor/password"
  guard nodes is [root, data, integrity, encryptors, encryptor, key] &&
    root.uri == uri &&
    root.name == "encryption" &&
    data.uri == uri &&
    data.name == "keyData" &&
    data.parent == root.id &&
    integrity.uri == uri &&
    integrity.name == "dataIntegrity" &&
    integrity.parent == root.id &&
    encryptors.uri == uri &&
    encryptors.name == "keyEncryptors" &&
    encryptors.parent == root.id &&
    encryptor.uri == uri &&
    encryptor.name == "keyEncryptor" &&
    encryptor.parent == encryptors.id &&
    encryptor.attribute("uri") == Some(password_uri) &&
    key.uri == password_uri &&
    key.name == "encryptedKey" &&
    key.parent == encryptor.id else {
    @failure.reject(
      "unsupported-docx", "Expected one Agile password key encryptor",
    )
  }
  let data_key_size = agile_key_size(data)
  let password_key_size = agile_key_size(key)
  let data_sha1 = data_key_size == 16
  let password_sha1 = password_key_size == 16
  let data_hash_block = if data_sha1 { 32 } else { 64 }
  let password_hash_block = if password_sha1 { 32 } else { 64 }
  let data_salt = agile_field(data, "saltValue", [16])
  let password_salt = agile_field(key, "saltValue", [16])
  guard key.attribute("spinCount") is Some(spin_text) else {
    @failure.reject(
      "malformed-package", "Missing Agile password iteration count",
    )
  }
  let spin = @string.parse_int(spin_text[:]) catch {
    _ =>
      @failure.reject(
        "malformed-package", "Invalid Agile password iteration count",
      )
  }
  guard spin >= 0 && spin <= 1000000 else {
    @failure.reject(
      "limit-exceeded", "Agile password iteration count exceeds budget",
    )
  }
  let verifier = agile_field(key, "encryptedVerifierHashInput", [16])
  let verifier_hash = agile_field(key, "encryptedVerifierHashValue", [
    password_hash_block,
  ])
  let encrypted_key = agile_field(key, "encryptedKeyValue", [data_key_size])
  let encrypted_hmac_key = agile_field(integrity, "encryptedHmacKey", [
    16, data_hash_block,
  ])
  let encrypted_hmac_value = agile_field(integrity, "encryptedHmacValue", [
    data_hash_block,
  ])
  let password = required_office_password(password)
  let digest = if password_sha1 {
    office_sha1_password_hash(password, password_salt[:], spin)
  } else {
    agile_sha512_password_hash(password, password_salt, spin)
  }
  let password_hash = Bytes::from_array(digest[:])
  let unlock = fn(block : Bytes, encrypted : Bytes) raise @failure.Failure {
    let block_key = agile_derive(
      password_sha1, password_hash, block, password_key_size,
    )
    agile_cbc(block_key[:], password_salt[:], encrypted[:])
  }
  let value = unlock(b"\xfe\xa7\xd2\x76\x3b\x4b\x9e\x79", verifier)
  let expected = unlock(b"\xd7\xaa\x0f\x6d\x30\x61\x34\x4e", verifier_hash)
  guard office_digest_matches(agile_digest(password_sha1, value), expected) else {
    @failure.reject("docx-password-required", "The DOCX password is incorrect")
  }
  let secret = unlock(b"\x14\x6e\x0b\xe7\xab\xac\xd0\xd6", encrypted_key)
  let key_iv = agile_derive(
    data_sha1, data_salt, b"\x5f\xb2\xad\x01\x0c\xb9\xe1\xf6", 16,
  )
  let value_iv = agile_derive(
    data_sha1, data_salt, b"\xa0\x67\x7f\x02\xb2\x2c\x84\x33", 16,
  )
  let hmac_key = agile_cbc(secret[:], key_iv[:], encrypted_hmac_key[:])
  let hmac_value = agile_cbc(secret[:], value_iv[:], encrypted_hmac_value[:])
  let digest = agile_hmac(data_sha1, hmac_key, payload)
  guard office_digest_matches(digest, hmac_value) else {
    @failure.reject(
      "malformed-package", "Agile encrypted Office package integrity check failed",
    )
  }
  let plain = Buffer(size_hint=size)
  let mut offset = 0
  while offset < size {
    let index = offset / 4096
    let block = Bytes::from_array(
      Array::makei(4, byte => (index >> (byte * 8)).to_byte()),
    )
    let iv = agile_derive(data_sha1, data_salt, block, 16)
    let count = (size - offset).min(4096)
    let end = offset + (count + 15) / 16 * 16
    let segment = agile_cbc(secret[:], iv[:], payload[8 + offset:8 + end])
    plain.write_bytes(segment[:count])
    offset += count
  }
  plain.to_bytes()
}
