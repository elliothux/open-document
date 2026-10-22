///|
fn math_fraction_markup(
  numerator : String,
  denominator : String,
  style~ : @layout.TextStyle? = None,
) -> String raise @failure.Failure {
  guard numerator.length() + denominator.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Fraction text exceeds budget")
  }
  guard [numerator, denominator].all(text => {
    !text.is_empty() &&
    @xml.valid_text(text) &&
    text.iter().all(ch => ch.to_int() >= 32 && ch != '\u2028' && ch != '\u2029')
  }) else {
    @failure.reject(
      "invalid-operation", "Fraction arguments require nonempty single-line text",
    )
  }
  let properties = match style {
    None => ""
    Some(style) => {
      let family = property_attribute(style.font)
      "<od:rPr xmlns:od=\"\{word_uri}\"><od:rFonts od:ascii=\"\{family}\" od:hAnsi=\"\{family}\"/><od:color od:val=\"\{style.color}\"/><od:sz od:val=\"\{(style.size*2).round().to_int()}\"/></od:rPr>"
    }
  }
  "<m:oMath xmlns:m=\"\{math_uri}\"><m:f><m:fPr><m:type m:val=\"bar\"/></m:fPr><m:num><m:r><m:rPr><m:sty m:val=\"p\"/></m:rPr>\{properties}<m:t xml:space=\"preserve\">\{@xml.escape_text(numerator)}</m:t></m:r></m:num><m:den><m:r><m:rPr><m:sty m:val=\"p\"/></m:rPr>\{properties}<m:t xml:space=\"preserve\">\{@xml.escape_text(denominator)}</m:t></m:r></m:den></m:f></m:oMath>"
}

///|
fn Session::math_fraction_target(
  self : Session,
  tree : WordTree,
  id : Int,
) -> (Int, @layout.MathFraction) raise @failure.Failure {
  self.check_document_protection()
  self.check_picture_context(tree)
  guard tree.nodes.get(id) is Some(node) &&
    node.uri == math_uri &&
    node.name == "oMath" &&
    tree.nodes.get(node.parent) is Some(paragraph) &&
    paragraph.uri == word_uri &&
    paragraph.name == "p" else {
    @failure.reject("invalid-operation", "Unknown inline fraction")
  }
  for parent = paragraph.parent; parent >= 0; parent = tree.nodes[parent].parent {
    guard tree.nodes[parent].uri == word_uri &&
      ["tc", "tr", "tbl", "body", "document"].contains(tree.nodes[parent].name) else {
      @failure.reject(
        "protected-content", "Fraction is in a protected container",
      )
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
    @failure.reject("protected-content", "Fraction contains opaque source")
  }
  let drawing = self.read_math_fraction(
    tree,
    id,
    @layout.TextStyle::new("Cambria Math", 11, "000000"),
  )
  guard drawing.content is @layout.Fraction(fraction) else {
    abort("Expected fraction")
  }
  (paragraph.id, fraction)
}

///|
pub fn Session::math_fractions(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let items : Array[Json] = []
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != math_uri || node.name != "oMath" {
      continue
    }
    guard items.length() < 256 else {
      @failure.reject("limit-exceeded", "Fraction catalog exceeds 256 items")
    }
    let mut numerator = ""
    let mut denominator = ""
    let reason = try {
      let (_, fraction) = self.math_fraction_target(tree, id)
      numerator = fraction.numerator
      denominator = fraction.denominator
      ""
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(message~, ..) => message
    }
    items.push({
      "id": id,
      "numerator": numerator,
      "denominator": denominator,
      "reason": reason,
    })
  }
  { "revision": revision, "items": items }
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
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["insert", "update", "delete"].contains(action) else {
    @failure.reject("invalid-operation", "Unknown fraction action")
  }
  let original = self.document()
  let tree = WordTree::new(original)
  self.check_picture_context(tree)
  let steps : Array[@xml.Edit] = []
  let mut after = self.selection
  let (candidate, paragraphs) = if action == "insert" {
    let markup = math_fraction_markup(numerator, denominator)
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
    let (paragraph, fraction) = self.math_fraction_target(tree, id)
    if action == "update" &&
      fraction.numerator == numerator &&
      fraction.denominator == denominator {
      return self.edit_state()
    }
    let node = tree.nodes[id]
    let markup = if action == "delete" {
      ""
    } else {
      math_fraction_markup(
        numerator,
        denominator,
        style=if tree
          .descendants(id)
          .any(id => {
            tree.nodes[id].uri == word_uri && tree.nodes[id].name == "rPr"
          }) {
          Some(fraction.style)
        } else {
          None
        },
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
      "unsupported-layout", "Fraction editing requires a complete layout",
    )
  }
  let mut bytes = 0
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Fraction history exceeds budget")
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
