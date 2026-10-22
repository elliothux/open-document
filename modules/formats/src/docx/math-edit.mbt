///|
fn Session::math_target(
  self : Session,
  tree : WordTree,
  id : Int,
) -> (Int, @layout.DrawingContent) raise @failure.Failure {
  self.check_document_protection()
  self.check_picture_context(tree)
  guard tree.nodes.get(id) is Some(node) &&
    node.uri == math_uri &&
    node.name == "oMath" &&
    tree.nodes.get(node.parent) is Some(paragraph) &&
    paragraph.uri == word_uri &&
    paragraph.name == "p" else {
    @failure.reject("invalid-operation", "Unknown inline math")
  }
  for parent = paragraph.parent; parent >= 0; parent = tree.nodes[parent].parent {
    guard tree.nodes[parent].uri == word_uri &&
      ["tc", "tr", "tbl", "body", "document"].contains(tree.nodes[parent].name) else {
      @failure.reject("protected-content", "Math is in a protected container")
    }
  }
  guard tree
    .descendants(paragraph.id)
    .all(id => {
      let node = tree.nodes[id]
      node.uri != word_uri ||
      !["ins", "del", "pPrChange", "rPrChange"].contains(node.name)
    }) else {
    @failure.reject(
      "protected-content", "Tracked mathematical edits require revision support",
    )
  }
  guard !tree.source[node.start:node.end].contains("<!--") &&
    !tree.source[node.start:node.end].contains("<?") else {
    @failure.reject("protected-content", "Math contains opaque source")
  }
  let drawing = self.read_inline_math(
    tree,
    id,
    @layout.TextStyle::new("Cambria Math", 11, "000000"),
  )
  (paragraph.id, drawing.content)
}

///|
fn Session::math_catalog(
  self : Session,
  revision : Int,
  kind : String,
) -> Json raise @failure.Failure {
  let scripts = kind == "script"
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let roots = tree.order.filter(id => {
    tree.nodes[id].uri == math_uri && tree.nodes[id].name == "oMath"
  })
  guard roots.length() <= 256 else {
    @failure.reject("limit-exceeded", "Math catalog exceeds 256 items")
  }
  let flow = self.flow()
  let paragraphs = flow.paragraphs.copy()
  paragraphs.append(
    flow.tables.map(table => table.rows.flatten().flatten()).flatten(),
  )
  let styles : Map[Int, @layout.TextStyle] = Map([])
  for paragraph in paragraphs {
    for span in paragraph.spans {
      if span.drawing is Some({ content, .. }) && content is Math(_) {
        styles[span.node] = math_content_style(content)
      }
    }
  }
  let items : Array[Json] = []
  for id in roots {
    if kind != "expression" &&
      tree.children[id].get(0) is Some(child) &&
      tree.nodes[child].uri == math_uri &&
      (
        tree.nodes[child].name == "rad" ||
        (if scripts {
          tree.nodes[child].name == "f"
        } else {
          ["sSub", "sSup", "sSubSup"].contains(tree.nodes[child].name)
        })
      ) {
      continue
    }
    let item : Map[String, Json] = { "id": Json(id) }
    for
      name in (if kind == "expression" {
        ["latex"]
      } else if scripts {
        ["base", "subscript", "superscript"]
      } else {
        ["numerator", "denominator"]
      }) {
      item[name] = Json("")
    }
    let mut format : Json = Json::null()
    let reason = try {
      let (_, content) = self.math_target(tree, id)
      if kind == "expression" && content is Math(formula) {
        item["latex"] = Json(math_latex(formula.expression))
      } else {
        let (is_script, arguments) = math_plain_arguments(content)
        guard scripts == is_script else {
          @failure.reject(
            "unsupported-math", "Mathematical expression kind does not match",
          )
        }
        let names = if scripts {
          ["base", "subscript", "superscript"]
        } else {
          ["numerator", "denominator"]
        }
        for index, name in names {
          item[name] = Json(arguments[index])
        }
      }
      guard styles.get(id) is Some(style) else {
        @failure.reject("protected-content", "Math layout is unavailable")
      }
      format = {
        "family": style.font,
        "size": style.size,
        "color": style.color,
      }
      ""
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(message~, ..) => message
    }
    item["reason"] = Json(reason)
    item["format"] = format
    items.push(Json::object(item))
  }
  { "revision": revision, "items": items }
}

///|
pub fn Session::math_fractions(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.math_catalog(revision, "fraction")
}

///|
pub fn Session::math_scripts(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.math_catalog(revision, "script")
}

///|
/// Native expression identities, canonical supported LaTeX and effective uniform appearances.
pub fn Session::math_expressions(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.math_catalog(revision, "expression")
}

///|
fn Session::edit_inline_math(
  self : Session,
  revision : Int,
  action : String,
  id : Int,
  content : @layout.DrawingContent,
  plain~ : Bool,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
  format? : CharacterFormat,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["insert", "update", "delete"].contains(action) else {
    @failure.reject("invalid-operation", "Unknown math action")
  }
  guard action != "delete" || format is None else {
    @failure.reject(
      "invalid-operation", "Deletion does not accept math formatting",
    )
  }
  let requested_style = format.map(math_fraction_style)
  let original = self.document()
  let tree = WordTree::new(original)
  self.check_picture_context(tree)
  let steps : Array[@xml.Edit] = []
  let mut after = self.selection
  let (candidate, paragraphs) = if action == "insert" {
    let markup = math_content_markup(
      math_with_style(
        content,
        requested_style.unwrap_or(math_content_style(content)),
      ),
      inherited=requested_style is None,
    )
    guard tree.order
      .filter(id => {
        tree.nodes[id].uri == math_uri && tree.nodes[id].name == "oMath"
      })
      .length() <
      256 else {
      @failure.reject("limit-exceeded", "Fraction catalog exceeds 256 items")
    }
    guard self.selection is Some(selection) else {
      @failure.reject("invalid-position", "Select a document position first")
    }
    let prepared = self.prepare_plain_range(selection, "")
    let document = prepared.map(edit => edit.document).unwrap_or(original)
    let position = prepared
      .bind(edit => edit.edit.after)
      .map(selection => selection.focus)
      .unwrap_or(selection.focus)
    if prepared is Some(edit) {
      steps.append(edit.edit.xml)
    }
    let (candidate, edit) = document.edit_source([
      self.paragraph_inline_source(document, position, _ => markup),
    ])
    steps.push(edit)
    let caret = {
      ..position,
      offset: position.offset + 1,
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    }
    after = Some({ anchor: caret, focus: caret, })
    (
      candidate,
      prepared.map(edit => edit.edit.paragraphs).unwrap_or([position.paragraph]),
    )
  } else {
    let (paragraph, current) = self.math_target(tree, id)
    guard !plain ||
      (
        content is Math({ expression: Fraction(_, _), .. }) &&
        current is Math({ expression: Fraction(_, _), .. })
      ) ||
      (
        content is Math({ expression: Scripts(_, _, _), .. }) &&
        current is Math({ expression: Scripts(_, _, _), .. })
      ) else {
      @failure.reject(
        "unsupported-math", "Mathematical expression kind does not match",
      )
    }
    if plain && action == "update" {
      ignore(math_plain_arguments(current))
    }
    let content = math_with_style(
      content,
      requested_style.unwrap_or(math_content_style(current)),
    )
    let explicit_style = tree
      .descendants(id)
      .any(id => tree.nodes[id].uri == word_uri && tree.nodes[id].name == "rPr")
    if action == "update" &&
      Json(content) == Json(current) &&
      (requested_style is None || explicit_style) {
      return self.edit_state()
    }
    let node = tree.nodes[id]
    let markup = if action == "delete" {
      ""
    } else {
      math_content_markup(
        content,
        inherited=requested_style is None && !explicit_style,
      )
    }
    let (candidate, edit) = original.edit_source([
      {
        node: paragraph,
        offset: node.start - tree.nodes[paragraph].start,
        length: node.end - node.start,
        xml: markup,
      },
    ])
    steps.push(edit)
    if after
      .map(selection => {
        selection.anchor.paragraph == paragraph ||
        selection.focus.paragraph == paragraph
      })
      .unwrap_or(false) {
      after = None
    }
    (candidate, [paragraph])
  }
  let layout = @layout.paginate(
    probe,
    self.flow_from(candidate),
    profile,
    images,
  )
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Math editing requires a complete layout",
    )
  }
  let mut bytes = 0
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Math history exceeds budget")
    }
    bytes += size
  }
  self.commit_edit(
    {
      xml: steps,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after,
      paragraphs,
      bytes,
    },
    candidate,
  )
  self.edit_result(paragraphs)
}

///|
/// Insert a plain inline fraction, or update/delete an explicitly identified one.
pub fn Session::edit_math_fraction(
  self : Session,
  revision : Int,
  action : String,
  id : Int,
  numerator : String,
  denominator : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
  format? : CharacterFormat,
) -> Json raise @failure.Failure {
  self.edit_inline_math(
    revision,
    action,
    id,
    Math(
      @layout.MathFormula::new(
        Fraction(Text(numerator), Text(denominator)),
        @layout.TextStyle::new("Cambria Math", 11, "000000"),
      ),
    ),
    probe~,
    plain=true,
    profile~,
    images~,
    format?,
  )
}

///|
/// Insert plain mathematical indices, or update/delete an explicitly identified script expression.
pub fn Session::edit_math_script(
  self : Session,
  revision : Int,
  action : String,
  id : Int,
  base : String,
  subscript : String,
  superscript : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
  format? : CharacterFormat,
) -> Json raise @failure.Failure {
  self.edit_inline_math(
    revision,
    action,
    id,
    Math(
      @layout.MathFormula::new(
        Scripts(
          Text(base),
          if subscript.is_empty() {
            None
          } else {
            Some(Text(subscript))
          },
          if superscript.is_empty() {
            None
          } else {
            Some(Text(superscript))
          },
        ),
        @layout.TextStyle::new("Cambria Math", 11, "000000"),
      ),
    ),
    probe~,
    plain=true,
    profile~,
    images~,
    format?,
  )
}
