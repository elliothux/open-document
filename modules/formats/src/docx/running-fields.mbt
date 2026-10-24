///|
fn running_field_code(instruction : String) -> String raise @failure.Failure {
  guard instruction.length() <= 256 else {
    @failure.reject("limit-exceeded", "Running field instruction is too long")
  }
  let tokens = instruction
    .replace_all(old="\t", new=" ")
    .split(" ")
    .filter(token => !token.is_empty())
    .map(token => token.to_owned())
    .collect()
  if tokens.length() >= 2 && tokens[0].to_upper() == "REF" {
    check_bookmark_name(tokens[1])
    let mut hyperlink = false
    let mut numbered = false
    let mut merge = false
    for i = 2; i < tokens.length(); {
      if tokens[i].to_lower() == "\\h" && !hyperlink {
        hyperlink = true
        continue i + 1
      } else if tokens[i].to_lower() == "\\n" && !numbered {
        numbered = true
        continue i + 1
      } else if tokens[i] == "\\*" &&
        i + 1 < tokens.length() &&
        tokens[i + 1].to_upper() == "MERGEFORMAT" &&
        !merge {
        merge = true
        continue i + 2
      } else {
        @failure.reject(
          "unsupported-layout", "Unsupported text reference switch",
        )
      }
    }
    guard merge || numbered else {
      @failure.reject(
        "unsupported-layout", "Text references require retained result formatting",
      )
    }
    return @layout.TextReference::{ bookmark: tokens[1], hyperlink, numbered, }.code()
  }
  if tokens.length() >= 2 && tokens[0].to_upper() == "SEQ" {
    let options = ["PAGE"]
    let mut control = ""
    let mut heading = ""
    let mut hidden = false
    for i = 2; i < tokens.length(); {
      let token = tokens[i].to_lower()
      if token == "\\h" && !hidden {
        hidden = true
        continue i + 1
      }
      if token == "\\s" && heading.is_empty() {
        guard i + 1 < tokens.length() else {
          @failure.reject(
            "unsupported-layout", "Missing sequence heading level",
          )
        }
        heading = ":heading=" + tokens[i + 1]
        continue i + 2
      }
      if ["\\c", "\\n", "\\r"].contains(token) && control.is_empty() {
        if token == "\\r" {
          guard i + 1 < tokens.length() else {
            @failure.reject("unsupported-layout", "Missing sequence restart")
          }
          control = ":restart=" + tokens[i + 1]
          continue i + 2
        }
        control = if token == "\\c" { ":repeat" } else { ":next" }
        continue i + 1
      }
      guard tokens[i] == "\\*" && i + 1 < tokens.length() else {
        @failure.reject("unsupported-layout", "Unsupported sequence switch")
      }
      options.push(tokens[i])
      options.push(tokens[i + 1])
      continue i + 2
    }
    let sequence = @layout.SequenceField::parse(
      "SEQ:" +
      tokens[1] +
      (if control == ":next" { "" } else { control }) +
      heading +
      // General formatting switches cancel the native hide switch in ONLYOFFICE.
      (if hidden && options.length() == 1 { ":hidden" } else { "" }),
    )
    let format = running_field_code(options.join(" ")).split(":").to_array()
    return {
      ..sequence,
      format: if format.length() == 2 {
        format[1].to_owned()
      } else {
        ""
      },
    }.code()
  }
  if tokens.length() >= 2 && tokens[0].to_upper() == "PAGEREF" {
    check_bookmark_name(tokens[1])
    let options = ["PAGE"]
    let mut hyperlink = false
    let mut relative = false
    let mut i = 2
    while i < tokens.length() {
      if tokens[i].to_lower() == "\\h" && !hyperlink {
        hyperlink = true
        i += 1
      } else if tokens[i].to_lower() == "\\p" && !relative {
        relative = true
        i += 1
      } else {
        guard tokens[i] == "\\*" && i + 1 < tokens.length() else {
          @failure.reject(
            "unsupported-layout", "Unsupported page reference switch",
          )
        }
        options.push(tokens[i])
        options.push(tokens[i + 1])
        i += 2
      }
    }
    let format = running_field_code(options.join(" ")).split(":").to_array()
    return @layout.PageReference::{
      bookmark: tokens[1],
      format: if format.length() == 2 {
        format[1].to_owned()
      } else {
        ""
      },
      hyperlink,
      relative,
    }.code()
  }
  guard [1, 3, 5].contains(tokens.length()) &&
    ["PAGE", "NUMPAGES"].contains(tokens[0].to_upper()) else {
    @failure.reject(
      "unsupported-layout", "Unsupported running field instruction",
    )
  }
  let mut format = ""
  let mut merge = false
  for i = 1; i < tokens.length(); i = i + 2 {
    guard tokens[i] == "\\*" else {
      @failure.reject("unsupported-layout", "Unsupported running field switch")
    }
    if tokens[i + 1].to_upper() == "MERGEFORMAT" && !merge {
      merge = true
      continue
    }
    guard format.is_empty() else {
      @failure.reject("unsupported-layout", "Duplicate running field format")
    }
    format = match tokens[i + 1] {
      "Arabic" | "ARABIC" | "arabic" => "decimal"
      "ROMAN" | "Roman" => "upperRoman"
      "roman" => "lowerRoman"
      "ALPHABETIC" => "upperLetter"
      "alphabetic" => "lowerLetter"
      _ =>
        @failure.reject(
          "unsupported-layout", "Unsupported running field format",
        )
    }
  }
  tokens[0].to_upper() + (if format.is_empty() { "" } else { ":" + format })
}

///|
fn WordTree::check_running_field_node(
  self : WordTree,
  id : Int,
  allowed : Array[String],
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  guard node.uri == word_uri &&
    node.attributes.all(a => a.uri == word_uri && allowed.contains(a.name)) &&
    [None, Some("0"), Some("false"), Some("off")].contains(
      node.attribute("fldLock", uri=word_uri),
    ) &&
    [
      None,
      Some("0"),
      Some("1"),
      Some("false"),
      Some("true"),
      Some("off"),
      Some("on"),
    ].contains(node.attribute("dirty", uri=word_uri)) else {
    @failure.reject("protected-content", "Extended or locked running field")
  }
}

///|
fn WordTree::check_field_text(
  self : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  guard self.children[id].is_empty() &&
    node.attributes.all(a => {
      a.uri == "http://www.w3.org/XML/1998/namespace" &&
      a.name == "space" &&
      ["preserve", "default"].contains(a.value)
    }) else {
    @failure.reject("protected-content", "Extended running field text")
  }
}

///|
// Keep the first result's formatting; all remaining cached result runs are derived.
fn keep_running_field(
  fields : Map[Int, String],
  results : Array[Int],
  code : String,
) -> Unit raise @failure.Failure {
  guard !results.is_empty() else {
    @failure.reject("protected-content", "Running field has no result text")
  }
  for index, id in results {
    fields[id] = if index == 0 { code } else { "" }
  }
}

///|
fn WordTree::running_fields(
  self : WordTree,
  paragraph : Int,
) -> Map[Int, String] raise @failure.Failure {
  let contents = self.contents
    .get(paragraph)
    .filter(toc => toc.reason.is_empty())
  let ignored = contents
    .map(toc => Set::from_array(toc.markers))
    .unwrap_or(Set([]))
  for id in self.descendants(paragraph) {
    if ignored.contains(id) {
      continue
    }
    let node = self.nodes[id]
    if node.uri == word_uri &&
      ["fldSimple", "fldChar", "instrText"].contains(node.name) {
      let parent = self.nodes[node.parent]
      guard (node.name == "fldSimple" && parent.id == paragraph) ||
        (
          node.name != "fldSimple" &&
          parent.name == "r" &&
          parent.uri == word_uri &&
          (
            parent.parent == paragraph ||
            (
              contents is Some(_) &&
              self.nodes[parent.parent].name == "hyperlink" &&
              self.nodes[parent.parent].uri == word_uri &&
              self.nodes[parent.parent].parent == paragraph
            )
          )
        ) else {
        @failure.reject(
          "protected-content", "Nested field containers require support",
        )
      }
    }
  }
  let fields : Map[Int, String] = Map([])
  let mut state = 0
  let mut instruction = ""
  let mut code = ""
  let mut results : Array[Int] = []
  let mut count = 0
  let children : Array[Int] = []
  for child in self.children[paragraph] {
    let node = self.nodes[child]
    if contents is Some(_) && node.uri == word_uri && node.name == "hyperlink" {
      self.check_hyperlink(child)
      children.append(self.children[child])
    } else {
      children.push(child)
    }
  }
  for child in children {
    let node = self.nodes[child]
    if node.name == "fldSimple" && node.uri == word_uri {
      guard state == 0 && node.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Nested running fields are unsupported",
        )
      }
      self.check_running_field_node(child, ["instr", "dirty", "fldLock"])
      let code = running_field_code(
        node.attribute("instr", uri=word_uri).unwrap_or(""),
      )
      let texts : Array[Int] = []
      for run in self.children[child] {
        guard self.nodes[run].uri == word_uri && self.nodes[run].name == "r" else {
          @failure.reject("protected-content", "Extended running field result")
        }
        for content in self.children[run] {
          let item = self.nodes[content]
          guard item.uri == word_uri && ["rPr", "t"].contains(item.name) else {
            @failure.reject(
              "protected-content", "Extended running field result",
            )
          }
          if item.name == "t" {
            self.check_field_text(content)
            texts.push(content)
          }
        }
      }
      keep_running_field(fields, texts, code)
      count += 1
    } else if node.name == "r" && node.uri == word_uri {
      for content in self.children[child] {
        if ignored.contains(content) {
          continue
        }
        let item = self.nodes[content]
        if item.uri != word_uri {
          continue
        }
        match item.name {
          "fldChar" => {
            self.check_running_field_node(content, [
              "fldCharType", "dirty", "fldLock",
            ])
            guard self.children[content].is_empty() &&
              item.text.trim().is_empty() else {
              @failure.reject(
                "protected-content", "Extended running field marker",
              )
            }
            match (state, item.attribute("fldCharType", uri=word_uri)) {
              (0, Some("begin")) => {
                state = 1
                instruction = ""
                results = []
              }
              (1, Some("separate")) => {
                code = running_field_code(instruction)
                state = 2
              }
              (2, Some("end")) => {
                keep_running_field(fields, results, code)
                count += 1
                state = 0
              }
              _ =>
                @failure.reject(
                  "protected-content", "Unbalanced or nested running field",
                )
            }
          }
          "instrText" => {
            guard state == 1 else {
              @failure.reject(
                "protected-content", "Running instruction outside a field",
              )
            }
            self.check_field_text(content)
            guard item.text.length() <= 256 - instruction.length() else {
              @failure.reject(
                "limit-exceeded", "Running field instruction is too long",
              )
            }
            instruction += item.text
          }
          "rPr" => ()
          "t" if state == 2 => {
            self.check_field_text(content)
            results.push(content)
          }
          _ if state != 0 =>
            @failure.reject(
              "protected-content", "Extended running field content",
            )
          _ => ()
        }
      }
    } else if state != 0 {
      @failure.reject(
        "protected-content", "Running field crosses a paragraph boundary",
      )
    }
    guard count <= 64 else {
      @failure.reject(
        "limit-exceeded", "Too many running fields in one paragraph",
      )
    }
  }
  guard state == 0 else {
    @failure.reject("protected-content", "Incomplete running field")
  }
  fields
}
