///|
let xmp_rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

///|
let xmp_dc = "http://purl.org/dc/elements/1.1/"

///|
fn xmp_property(key : String) -> (String, String) {
  match key {
    "Title" => (xmp_dc, "title")
    "Author" => (xmp_dc, "creator")
    "Subject" => (xmp_dc, "description")
    _ => ("http://ns.adobe.com/pdf/1.3/", "Keywords")
  }
}

///|
fn PdfSession::xmp_metadata(
  self : PdfSession,
) -> (@xml.Document, @xml.Node, Map[String, @xml.Node])? raise @failure.Failure {
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  let metadata = raw(catalog, "Metadata")
  if metadata == @syntax.PdfNull {
    return None
  }
  let bytes = pdf_bound(self.budget, () => stream_bytes(self.document, metadata))
  let document = @xml.Document::parse(bytes, "PDF XMP", 64, 1048576)
  let nodes : Array[@xml.Node] = document.nodes().iter().collect()
  guard nodes.length() <= 10000 else {
    @failure.reject("limit-exceeded", "XMP metadata has too many nodes")
  }
  let descriptions = nodes.filter(node => {
    node.uri == xmp_rdf && node.name == "Description"
  })
  guard descriptions.length() == 1 else {
    @failure.reject(
      "protected-content", "XMP requires one RDF description for metadata editing",
    )
  }
  let description = descriptions[0]
  let leaves : Map[String, @xml.Node] = Map([])
  for key in ["Title", "Author", "Subject", "Keywords"] {
    let (uri, name) = xmp_property(key)
    guard !description.attributes.any(attribute => {
      attribute.uri == uri && attribute.name == name
    }) else {
      @failure.reject(
        "protected-content", "Attribute-form XMP metadata requires explicit synchronization",
      )
    }
    let properties = nodes.filter(node => {
      node.parent == description.id && node.uri == uri && node.name == name
    })
    guard properties.length() <= 1 else {
      @failure.reject(
        "protected-content", "Duplicate XMP metadata properties are protected",
      )
    }
    if properties.is_empty() {
      continue
    }
    let property = properties[0]
    let children = nodes.filter(node => node.parent == property.id)
    if key == "Keywords" {
      guard children.is_empty() else {
        @failure.reject(
          "protected-content", "Structured XMP keywords are protected",
        )
      }
      leaves[key] = property
    } else {
      let container = if key == "Author" { "Seq" } else { "Alt" }
      guard children.length() == 1 &&
        children[0].uri == xmp_rdf &&
        children[0].name == container else {
        @failure.reject(
          "protected-content", "Unsupported XMP metadata container",
        )
      }
      let entries = nodes.filter(node => node.parent == children[0].id)
      let defaults = entries.filter(node => {
        node.uri == xmp_rdf &&
        node.name == "li" &&
        (
          key == "Author" ||
          node
          .attribute("lang", uri="http://www.w3.org/XML/1998/namespace")
          .unwrap_or("") ==
          "x-default"
        )
      })
      guard defaults.length() == 1 &&
        (key != "Author" || entries.length() == 1) &&
        !document.nodes().any(node => node.parent == defaults[0].id) else {
        @failure.reject(
          "protected-content", "Ambiguous XMP metadata text is protected",
        )
      }
      leaves[key] = defaults[0]
    }
  }
  Some((document, description, leaves))
}

///|
fn xmp_property_xml(
  key : String,
  value : String,
) -> String raise @failure.Failure {
  let escaped = @xml.escape_text(value)
  if key == "Keywords" {
    return "<pdf:Keywords xmlns:pdf=\"http://ns.adobe.com/pdf/1.3/\">" +
      escaped +
      "</pdf:Keywords>"
  }
  let (_, name) = xmp_property(key)
  let inner = if key == "Author" {
    "<rdf:Seq><rdf:li>" + escaped + "</rdf:li></rdf:Seq>"
  } else {
    "<rdf:Alt><rdf:li xml:lang=\"x-default\">" + escaped + "</rdf:li></rdf:Alt>"
  }
  "<dc:" +
  name +
  " xmlns:dc=\"" +
  xmp_dc +
  "\" xmlns:rdf=\"" +
  xmp_rdf +
  "\">" +
  inner +
  "</dc:" +
  name +
  ">"
}

///|
fn PdfSession::update_xmp(
  self : PdfSession,
  tx : PdfTransaction,
  fields : Map[String, String],
) -> Unit raise @failure.Failure {
  guard self.xmp_metadata() is Some((document, description, leaves)) else {
    return
  }
  let updates : Map[Int32, String] = Map([])
  let addition = StringBuilder()
  for key in ["Title", "Author", "Subject", "Keywords"] {
    if fields.get(key) is Some(value) {
      if leaves.get(key) is Some(node) {
        updates[node.id] = value
      } else {
        addition.write_string(xmp_property_xml(key, value))
      }
    }
  }
  let source : Array[@xml.SourceChange] = []
  let added = addition.to_string()
  if !added.is_empty() {
    if description.empty {
      let original = document.source()[description.start:description.end].to_owned()
      source.push({
        node: description.id,
        offset: 0,
        length: description.end - description.start,
        xml: original[:original.length() - 2].to_owned() +
        ">" +
        added +
        "</" +
        description.qualified +
        ">",
      })
    } else {
      source.push({
        node: description.id,
        offset: description.closing_start - description.start,
        length: 0,
        xml: added,
      })
    }
  }
  let (updated, _) = document.edit_text(updates, source~)
  let catalog = tx.object(self.document.root())
  guard raw(catalog, "Metadata") is PdfIndirect(id) else {
    @failure.reject("protected-content", "Direct XMP streams are protected")
  }
  pdf_bound(self.budget, () => {
    guard tx.object(id) is PdfStreamObject(original) else {
      @failure.reject("invalid-pdf", "XMP must be a stream")
    }
    let dictionary = original.dictionary
      .deep_copy()
      .remove_dict_entry(pdf_name("Filter"))
      .remove_dict_entry(pdf_name("DecodeParms"))
      .with_entry(
        pdf_name("Length"),
        @syntax.PdfInteger(updated.bytes().length()),
      )
    tx.objects[id] = @syntax.pdf_stream(
      dictionary,
      @syntax.StreamGot(updated.bytes()),
    )
  })
}
