///|
pub(all) struct Attribute {
  uri : String
  name : String
  value : String
  start : Int
  end : Int
}

///|
pub(all) struct Node {
  id : Int
  uri : String
  name : String
  qualified : String
  parent : Int
  start : Int
  opening_end : Int
  closing_start : Int
  end : Int
  text : String
  attributes : ReadOnlyArray[Attribute]
  namespaces : ReadOnlyArray[(String, String)]
  empty : Bool
}

///|
pub struct Document {
  priv source : String
  priv nodes : Array[Node]
  priv text_spans : Array[Array[(Int, Int)]]
  priv declaration_end : Int
  priv declaration : String
  priv part : String
  priv depth_limit : Int
  priv byte_limit : Int
  priv origin : String
  priv next_id : Int
}

///|
pub fn Document::parse(
  bytes : Bytes,
  part : String,
  depth_limit : Int,
  byte_limit : Int,
) -> Document raise @failure.Failure {
  guard bytes.length() <= byte_limit && depth_limit >= 0 else {
    @failure.reject("limit-exceeded", "XML budget exceeded", part~)
  }
  let encoding = if bytes.length() >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe {
    "utf-16le"
  } else if bytes.length() >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff {
    "utf-16be"
  } else {
    "utf-8"
  }
  let source = try {
    if encoding == "utf-8" {
      let start = if bytes.length() >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf {
        3
      } else {
        0
      }
      @utf8.decode(bytes[start:])
    } else {
      @utf16.decode(
        bytes[2:],
        endianness=if encoding == "utf-16le" {
          @utf16.Little
        } else {
          @utf16.Big
        },
      )
    }
  } catch {
    _ =>
      @failure.reject("malformed-xml", "Invalid XML encoding", part~, offset=0)
  }
  // Reject before the parser can expand an internal subset; no entity I/O exists.
  reject_dtd(source, part)
  guard valid_text(source) else {
    @failure.reject("malformed-xml", "Invalid XML character", part~)
  }
  let (parsed_source, declaration_end, declaration) = declaration(
    source, encoding, part,
  )
  let reader = @parser.NamespaceReader::from_string(parsed_source)
  let nodes : Array[Node] = []
  let text_spans : Array[Array[(Int, Int)]] = []
  let text_builders : Array[StringBuilder] = []
  let stack : Array[Int] = []
  for ;; {
    let event = reader.read_event() catch {
      @parser.At(error~, span~) =>
        @failure.reject(
          "malformed-xml",
          error.to_string(),
          part~,
          offset=span.start.offset,
        )
    }
    match event.kind {
      Decl(..) =>
        @failure.reject(
          "malformed-xml",
          "Misplaced XML declaration",
          part~,
          offset=event.span.start.offset,
        )
      Start(element) | Empty(element) => {
        guard stack.length() < depth_limit else {
          @failure.reject(
            "limit-exceeded",
            "XML depth budget exceeded",
            part~,
            offset=event.span.start.offset,
          )
        }
        let attributes : Array[Attribute] = []
        for attribute in element.attributes {
          attributes.push({
            uri: attribute.name.namespace_uri.unwrap_or(""),
            name: attribute.name.local_name,
            value: attribute.value,
            start: attribute.value_span.start.offset,
            end: attribute.value_span.end.offset,
          })
        }
        let empty = event.kind is Empty(_)
        nodes.push({
          id: nodes.length(),
          uri: element.name.namespace_uri.unwrap_or(""),
          name: element.name.local_name,
          qualified: element.name.qualified_name,
          parent: stack.last().unwrap_or(-1),
          start: event.span.start.offset,
          opening_end: event.span.end.offset,
          closing_start: event.span.end.offset,
          end: event.span.end.offset,
          text: "",
          attributes: ReadOnlyArray::from_array(attributes),
          namespaces: ReadOnlyArray::from_array(
            element.namespace_declarations.map(declaration => {
              (declaration.prefix.unwrap_or(""), declaration.namespace_uri)
            }),
          ),
          empty,
        })
        text_spans.push([])
        text_builders.push(StringBuilder())
        if !empty {
          stack.push(nodes.length() - 1)
        }
      }
      End(_) => {
        guard stack.pop() is Some(id) else {
          @failure.reject("malformed-xml", "Unmatched closing element", part~)
        }
        nodes[id] = {
          ..nodes[id],
          closing_start: event.span.start.offset,
          end: event.span.end.offset,
          text: text_builders[id].to_string(),
        }
      }
      Text(text) | CData(text) =>
        if stack.last() is Some(id) {
          text_builders[id].write_string(text)
          text_spans[id].push((event.span.start.offset, event.span.end.offset))
        }
      Eof => break
      PI(target~, ..) => {
        guard !target.contains(":") else {
          @failure.reject(
            "malformed-xml",
            "Colon in processing instruction target",
            part~,
            offset=event.span.start.offset,
          )
        }
      }
      _ => ()
    }
  }
  guard stack.is_empty() && !nodes.is_empty() else {
    @failure.reject("malformed-xml", "Incomplete XML document", part~)
  }
  {
    source,
    nodes,
    text_spans,
    declaration_end,
    declaration,
    part,
    depth_limit,
    byte_limit,
    origin: if declaration_end > 0 && source[:declaration_end] != declaration {
      declaration + source[declaration_end:].to_owned()
    } else {
      source
    },
    next_id: nodes.length(),
  }
}

///|
pub fn Document::nodes(self : Document) -> ReadOnlyArray[Node] {
  ReadOnlyArray::from_array(self.nodes)
}

///|
pub fn Node::attribute(
  self : Node,
  name : String,
  uri? : String = "",
) -> String? {
  for attribute in self.attributes {
    if attribute.name == name && attribute.uri == uri {
      return Some(attribute.value)
    }
  }
  None
}

///|
pub fn valid_text(text : String) -> Bool {
  for ch in text {
    let value = ch.to_int()
    if !(value == 9 ||
      value == 10 ||
      value == 13 ||
      (value >= 32 && value <= 0xd7ff) ||
      (value >= 0xe000 && value <= 0xfffd) ||
      (value >= 0x10000 && value <= 0x10ffff)) {
      return false
    }
  }
  true
}

///|
/// Splices source spans; unknown markup and namespace bindings stay in place.
pub fn Document::edit_text(
  self : Document,
  replacements : Map[Int, String],
  source? : Array[SourceChange] = [],
) -> (Document, Edit) raise @failure.Failure {
  let patches = self.source_patches(source)
  let mut added = 0
  for id, text in replacements {
    guard valid_text(text) else {
      @failure.reject(
        "invalid-operation",
        "Invalid XML text replacement",
        part=self.part,
      )
    }
    let index = self.node_index(id)
    let node = self.nodes[index]
    guard !self.nodes.iter().any(child => child.parent == id) else {
      @failure.reject(
        "invalid-operation",
        "Cannot replace element with children",
        part=self.part,
      )
    }
    guard text.length() <= self.byte_limit - added else {
      @failure.reject(
        "limit-exceeded",
        "XML replacement budget exceeded",
        part=self.part,
      )
    }
    let escaped = @parser.escape(text).replace(old="\r", new="&#13;")
    guard escaped.length() <= self.byte_limit - added else {
      @failure.reject(
        "limit-exceeded",
        "XML replacement budget exceeded",
        part=self.part,
      )
    }
    added += escaped.length()
    if node.empty {
      patches.push(
        self.source_patch(
          id,
          node.opening_end - 2,
          node.end,
          ">" + escaped + "</" + node.qualified + ">",
        ),
      )
    } else if self.text_spans[index].is_empty() {
      patches.push(
        self.source_patch(id, node.opening_end, node.opening_end, escaped),
      )
    } else {
      for i, (start, end) in self.text_spans[index] {
        patches.push(
          self.source_patch(id, start, end, if i == 0 { escaped } else { "" }),
        )
      }
    }
    let xml_uri = "http://www.w3.org/XML/1998/namespace"
    let space = for attribute in node.attributes {
      if attribute.uri == xml_uri && attribute.name == "space" {
        break Some(attribute)
      }
    } nobreak {
      None
    }
    if space is Some(attribute) {
      if attribute.value != "preserve" {
        patches.push(
          self.source_patch(id, attribute.start, attribute.end, "preserve"),
        )
      }
    } else {
      let insertion = node.opening_end - (if node.empty { 2 } else { 1 })
      patches.push(
        self.source_patch(id, insertion, insertion, " xml:space=\"preserve\""),
      )
    }
  }
  self.prepare_edit(patches, forward=true, record=true)
}

///|
pub fn Document::replace(
  self : Document,
  replacements : Map[Int, String],
) -> Bytes raise @failure.Failure {
  self.edit_text(replacements).0.bytes()
}
