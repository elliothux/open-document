///|
pub(all) struct Relationship {
  owner : String
  id : String
  kind : String
  target : String
  external : Bool
}

///|
pub struct Package {
  archive : @archive.Package
  names : Map[String, String]
  types : Map[String, String]
  relationships : Array[Relationship]
  budget : @archive.Budget
  signed : Bool
  mut closed : Bool
}

///|
pub fn Package::open(
  bytes : Bytes,
  budget : @archive.Budget,
) -> Package raise @failure.Failure {
  let archive = @archive.Package::open(bytes, budget)
  errdefer archive.close()
  let names : Map[String, String] = Map([])
  for name in archive.names() {
    if name.has_suffix("/") {
      continue
    }
    if name != "[Content_Types].xml" {
      part_name(name)
    }
    let key = name.to_lower()
    guard !names.contains(key) else {
      @failure.reject(
        "malformed-opc",
        "Part names collide ignoring case",
        part=name,
      )
    }
    names[key] = name
  }
  let (types, relationships, signed) = read_metadata(names, budget, name => {
    archive.read(name)
  })
  { archive, names, types, relationships, budget, signed, closed: false, }
}

///|
fn Package::check(self : Package) -> Unit raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "OPC package is closed")
  }
}

///|
pub fn Package::relationships(
  self : Package,
  replacements~ : Map[String, Bytes] = Map([]),
) -> ReadOnlyArray[Relationship] raise @failure.Failure {
  self.check()
  if replacements
    .keys()
    .any(name => {
      name.to_lower().has_suffix(".rels") ||
      name == "[Content_Types].xml" ||
      !self.names.contains(name.to_lower())
    }) {
    self.validate_changes(replacements)
    let (_, relationships, _) = self.replacement_metadata(replacements, [])
    return ReadOnlyArray::from_array(relationships)
  }
  ReadOnlyArray::from_array(self.relationships)
}

///|
pub fn Package::content_type(
  self : Package,
  name : String,
) -> String? raise @failure.Failure {
  self.check()
  self.types.get(name.to_lower())
}

///|
pub fn Package::read(
  self : Package,
  name : String,
) -> Bytes raise @failure.Failure {
  self.check()
  guard self.names.get(name.to_lower()) is Some(actual) else {
    @failure.reject("missing-part", "Part does not exist", part=name)
  }
  self.archive.read(actual)
}

///|
pub fn Package::xml(
  self : Package,
  name : String,
) -> @xml.Document raise @failure.Failure {
  @xml.Document::parse(
    self.read(name),
    name,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
}

///|
pub fn Package::save(
  self : Package,
  replacements : Map[String, Bytes],
  removed~ : Array[String] = [],
) -> Bytes raise @failure.Failure {
  self.validate_changes(replacements, removed~)
  let output = self.archive.save(replacements, removed~)
  let candidate = Package::open(output, {
    ..self.budget,
    file_bytes: self.budget.output_bytes,
    retained_bytes: self.budget.output_bytes,
  })
  defer candidate.close()
  candidate.validate_xml(replacements)
  output
}

///|
pub fn Package::validate_changes(
  self : Package,
  replacements : Map[String, Bytes],
  removed~ : Array[String] = [],
) -> Unit raise @failure.Failure {
  self.check()
  guard !self.signed else {
    @failure.reject(
      "unsupported-package", "Signed packages cannot be safely rewritten",
    )
  }
  let names : Map[String, Bool] = Map([])
  for key, name in self.names {
    if !removed.contains(name) {
      names[key] = true
    }
  }
  for name, _ in replacements {
    if name != "[Content_Types].xml" {
      part_name(name)
    }
    let key = name.to_lower()
    guard !names.contains(key) || self.names.get(key) == Some(name) else {
      @failure.reject(
        "malformed-opc",
        "Part names collide ignoring case",
        part=name,
      )
    }
    names[key] = true
  }
  ignore(self.archive.validate_changes(replacements, removed~))
  if !removed.is_empty() ||
    replacements
    .keys()
    .any(name => {
      name.to_lower().has_suffix(".rels") ||
      name == "[Content_Types].xml" ||
      !self.names.contains(name.to_lower())
    }) {
    let (_, _, signed) = self.replacement_metadata(replacements, removed)
    guard !signed else {
      @failure.reject("unsupported-package", "Cannot introduce signature parts")
    }
  }
}

///|
fn Package::replacement_metadata(
  self : Package,
  replacements : Map[String, Bytes],
  removed : Array[String],
) -> (Map[String, String], Array[Relationship], Bool) raise @failure.Failure {
  let names = self.names.copy()
  for name in removed {
    names.remove(name.to_lower())
  }
  for name, _ in replacements {
    names[name.to_lower()] = name
  }
  read_metadata(names, self.budget, name => {
    match replacements.get(name) {
      Some(bytes) => bytes
      None => self.read(name)
    }
  })
}

///|
fn Package::validate_xml(
  self : Package,
  changed : Map[String, Bytes],
) -> Unit raise @failure.Failure {
  guard !self.signed else {
    @failure.reject("unsupported-package", "Cannot introduce signature parts")
  }
  for name, _ in changed {
    if self.content_type(name) is Some(kind) &&
      (kind.has_suffix("+xml") || kind.has_suffix("/xml")) {
      ignore(self.xml(name))
    }
  }
}

///|
/// Creates and validates an OPC package from its explicit parts.
pub fn Package::create(
  parts : Map[String, Bytes],
  budget : @archive.Budget,
) -> Package raise @failure.Failure {
  let archive = @archive.Package::create(parts, budget)
  defer archive.close()
  let candidate = Package::open(archive.save(Map([])), budget)
  errdefer candidate.close()
  candidate.validate_xml(parts)
  candidate
}

///|
pub fn Package::decoded_bytes(self : Package) -> Int raise @failure.Failure {
  self.archive.decoded_bytes()
}

///|
pub fn Package::close(self : Package) -> Unit {
  self.closed = true
  self.archive.close()
  self.names.clear()
  self.types.clear()
  self.relationships.clear()
}
