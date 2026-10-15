///|
fn Session::part_xml(
  self : Session,
  name : String,
) -> @xml.Document raise @failure.Failure {
  ignore(self.document())
  if name == self.main {
    return self.document()
  }
  match self.parts.get(name) {
    Some(document) => document
    None => self.opc.xml(name)
  }
}

///|
fn Session::replacements(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
) -> Map[String, Bytes] {
  let replacements = Map([])
  for name, document in parts {
    if !document.is_original() {
      replacements[name] = document.bytes()
    }
  }
  if !document.is_original() {
    replacements[self.main] = document.bytes()
  }
  replacements
}
