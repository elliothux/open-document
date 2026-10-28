///|
fn PdfSession::annotation_nodes(
  self : PdfSession,
) -> Map[Int32, (SourcePage, @syntax.PdfObject)] raise @failure.Failure {
  let nodes : Map[Int32, (SourcePage, @syntax.PdfObject)] = Map([])
  for page in self.pages {
    for
      reference in annotation_refs(
        self.document,
        self.document.lookup_object_or_null(page.number),
      ) {
      guard reference is PdfIndirect(n) else {
        let object = resolve(self.document, reference)
        guard raw(object, "IRT") == @syntax.PdfNull &&
          raw(object, "Popup") == @syntax.PdfNull &&
          !is_name(raw(object, "Subtype"), "Popup") else {
          @failure.reject(
            "protected-content", "Direct annotation thread relationships are protected",
          )
        }
        continue
      }
      guard !nodes.contains(n) && nodes.length() < 4096 else {
        @failure.reject(
          "protected-content", "Duplicate or excessive annotation relationships",
        )
      }
      nodes[n] = (page, self.document.lookup_object_or_null(n))
    }
  }
  nodes
}

///|
fn PdfSession::check_annotation_relationships(
  self : PdfSession,
  page : SourcePage,
  n : Int32,
) -> Unit raise @failure.Failure {
  self.check_annotation_chain(page, n, self.annotation_nodes())
}

///|
fn PdfSession::check_annotation_chain(
  self : PdfSession,
  page : SourcePage,
  n : Int32,
  nodes : Map[Int32, (SourcePage, @syntax.PdfObject)],
) -> Unit raise @failure.Failure {
  let catalog = resolve(
    self.document,
    @syntax.PdfIndirect(self.document.root()),
  )
  guard raw(catalog, "StructTreeRoot") == @syntax.PdfNull else {
    @failure.reject(
      "protected-content", "Tagged annotation structure is protected",
    )
  }
  guard nodes.get(n) is Some((owner, _)) && owner.id == page.id else {
    @failure.reject(
      "invalid-operation", "Annotation is not on the selected page",
    )
  }
  let visited : Map[Int32, Bool] = Map([])
  let mut current = n
  while true {
    guard visited.length() < 64 &&
      !visited.contains(current) &&
      nodes.get(current) is Some((page, object)) else {
      @failure.reject(
        "protected-content", "Annotation reply chain is cyclic or detached",
      )
    }
    visited[current] = true
    let reason = annotation_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    guard raw(object, "P") == @syntax.PdfNull ||
      raw(object, "P") == @syntax.PdfIndirect(page.number) else {
      @failure.reject(
        "protected-content", "Annotation page relationship is inconsistent",
      )
    }
    if raw(object, "Popup") is PdfIndirect(popup) {
      guard nodes.get(popup) is Some((popupPage, popupObject)) &&
        popupPage.id == page.id &&
        is_name(raw(popupObject, "Subtype"), "Popup") &&
        raw(popupObject, "Parent") == @syntax.PdfIndirect(current) else {
        @failure.reject(
          "protected-content", "Annotation popup relationship is inconsistent",
        )
      }
      let popupFlags = raw(popupObject, "F")
      guard popupFlags == @syntax.PdfNull ||
        (integer(popupFlags) & (64 | 128 | 512)) == 0 else {
        @failure.reject("protected-content", "Locked PDF popup")
      }
      guard raw(popupObject, "P") == @syntax.PdfNull ||
        raw(popupObject, "P") == @syntax.PdfIndirect(page.number) else {
        @failure.reject(
          "protected-content", "Popup page relationship is inconsistent",
        )
      }
      for key in ["A", "AA", "OC", "StructParent", "IRT", "Popup"] {
        guard raw(popupObject, key) == @syntax.PdfNull else {
          @failure.reject(
            "protected-content",
            "Popup relationship is protected: " + key,
          )
        }
      }
    }
    match raw(object, "IRT") {
      PdfNull => break
      PdfIndirect(parent) => current = parent
      _ =>
        @failure.reject(
          "protected-content", "Annotation reply parent must be indirect",
        )
    }
  }
}

///|
fn PdfSession::annotation_thread_members(
  self : PdfSession,
  n : Int32,
  whole : Bool,
) -> Map[Int32, Bool] raise @failure.Failure {
  let nodes = self.annotation_nodes()
  let mut root = n
  if whole {
    let visited : Map[Int32, Bool] = Map([])
    while true {
      guard !visited.contains(root) &&
        visited.length() < 64 &&
        nodes.get(root) is Some((_, object)) else {
        @failure.reject(
          "protected-content", "Annotation reply chain is cyclic or detached",
        )
      }
      visited[root] = true
      match raw(object, "IRT") {
        PdfNull => break
        PdfIndirect(parent) => root = parent
        _ =>
          @failure.reject(
            "protected-content", "Annotation reply parent must be indirect",
          )
      }
    }
  }
  let members : Map[Int32, Bool] = Map([(root, true)])
  if whole {
    let mut changed = true
    while changed {
      changed = false
      for id, (_, object) in nodes {
        if raw(object, "IRT") is PdfIndirect(parent) &&
          members.contains(parent) &&
          !members.contains(id) {
          members[id] = true
          changed = true
        }
      }
    }
  }
  let annotations = members.keys().collect()
  for id in annotations {
    let (page, object) = nodes[id]
    self.check_annotation_chain(page, id, nodes)
    if raw(object, "Popup") is PdfIndirect(popup) {
      members[popup] = true
    }
  }
  members
}

///|
fn PdfSession::delete_annotation_members(
  self : PdfSession,
  tx : PdfTransaction,
  n : Int32,
  whole : Bool,
) -> Unit raise {
  let removed = self.annotation_thread_members(n, whole)
  for page in self.pages {
    let object = tx.object(page.number)
    let refs = annotation_refs(self.document, object)
    let retained = refs.filter(reference => {
      match reference {
        PdfIndirect(id) => !removed.contains(id)
        _ => true
      }
    })
    if retained.length() != refs.length() {
      tx.objects[page.number] = object.with_entry(
        pdf_name("Annots"),
        @syntax.PdfArray(retained),
      )
    }
  }
  let reachable = tx.reachable_objects()
  guard !removed.iter().any(entry => reachable.contains(entry.0)) else {
    @failure.reject(
      "protected-content", "Retained replies or content refer to the annotation; delete the whole thread explicitly",
    )
  }
}

///|
pub fn PdfSession::delete_annotation_thread(
  self : PdfSession,
  revision : Int32,
  page : String,
  annotation : String,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  pdf_bound(self.budget, () => {
    let n = self.annotation_target(self.page(page), annotation)
    self.delete_annotation_members(tx, n, true)
    tx.commit(self.current)
  })
}

///|
pub fn PdfSession::annotation_thread(
  self : PdfSession,
  revision : Int32,
  page : String,
  annotation : String,
) -> Json raise @failure.Failure {
  self.check(revision)
  pdf_bound(self.budget, () => {
    let n = self.annotation_target(self.page(page), annotation)
    let members = self.annotation_thread_members(n, true)
    let entries : Array[Json] = []
    for p in self.pages {
      for
        reference in annotation_refs(
          self.document,
          self.document.lookup_object_or_null(p.number),
        ) {
        guard reference is PdfIndirect(id) && members.contains(id) else {
          continue
        }
        let object = self.document.lookup_object_or_null(id)
        if is_name(raw(object, "Subtype"), "Popup") {
          continue
        }
        entries.push({
          "id": "\{id}:\{self.generations.get(id).unwrap_or(0)}",
          "page": p.id,
          "parent": match raw(object, "IRT") {
            PdfIndirect(parent) =>
              "\{parent}:\{self.generations.get(parent).unwrap_or(0)}"
            _ => ""
          },
          "text": if raw(object, "Contents") == @syntax.PdfNull {
            ""
          } else {
            pdf_text_string(raw(object, "Contents"))
          },
          "author": if raw(object, "T") == @syntax.PdfNull {
            ""
          } else {
            pdf_text_string(raw(object, "T"))
          },
        })
      }
    }
    { "revision": revision, "entries": entries }
  })
}

///|
fn PdfTransaction::annotation_popup(
  self : PdfTransaction,
  page : SourcePage,
  parent : Int32,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject raise {
  let p = annotation_placement(page, object)
  let width = page.width.min(200)
  let height = page.height.min(100)
  let x = (p.x + p.width).min(page.width - width).max(0)
  let y = p.y.min(page.height - height).max(0)
  let (a, b) = page.matrix.inverse().point(x, y)
  let (c, d) = page.matrix.inverse().point(x + width, y + height)
  self.add(
    dict([
      ("Type", tag("Annot")),
      ("Subtype", tag("Popup")),
      ("Parent", @syntax.PdfIndirect(parent)),
      ("P", @syntax.PdfIndirect(page.number)),
      ("Rect", pdf_rectangle(a.min(c), b.min(d), a.max(c), b.max(d))),
      ("Open", @syntax.PdfBoolean(false)),
    ]),
  )
}

///|
pub fn PdfSession::reply_annotation(
  self : PdfSession,
  revision : Int32,
  page : String,
  annotation : String,
  text : String,
  author : String,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  check_pdf_text(text)
  check_pdf_text(author)
  pdf_bound(self.budget, () => {
    let page = self.page(page)
    let n = self.annotation_target(page, annotation)
    let object = tx.object(n)
    let refs = annotation_refs(self.document, tx.object(page.number)).copy()
    guard refs.length() <= 4093 else {
      @failure.reject("limit-exceeded", "Annotation replies exceed page budget")
    }
    if raw(object, "Popup") == @syntax.PdfNull {
      let popup = tx.annotation_popup(page, n, object)
      tx.objects[n] = object.with_entry(pdf_name("Popup"), popup)
      refs.push(popup)
    }
    let p = annotation_placement(page, object)
    let width = page.width.min(20)
    let height = page.height.min(20)
    let x = p.x.min(page.width - width).max(0)
    let y = p.y.min(page.height - height).max(0)
    let (a, b) = page.matrix.inverse().point(x, y)
    let (c, d) = page.matrix.inverse().point(x + width, y + height)
    let reply = dict([
      ("Type", tag("Annot")),
      ("Subtype", tag("Text")),
      ("IRT", @syntax.PdfIndirect(n)),
      ("RT", tag("R")),
      ("T", pdf_string(author)),
      ("Contents", pdf_string(text)),
      ("Rect", pdf_rectangle(a.min(c), b.min(d), a.max(c), b.max(d))),
      ("P", @syntax.PdfIndirect(page.number)),
      ("F", @syntax.PdfInteger(4)),
      ("Name", tag("Comment")),
    ])
    guard tx.add(annotation_appearance(tx, reply)) is PdfIndirect(replyId) else {
      abort("Expected reply identity")
    }
    let popup = tx.annotation_popup(page, replyId, reply)
    tx.objects[replyId] = tx
      .object(replyId)
      .with_entry(pdf_name("Popup"), popup)
    refs.append([@syntax.PdfIndirect(replyId), popup])
    tx.objects[page.number] = tx
      .object(page.number)
      .with_entry(pdf_name("Annots"), @syntax.PdfArray(refs))
    tx.commit(self.current)
  })
}
