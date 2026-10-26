///|
fn Session::flow_sections(
  self : Session,
  tree : WordTree,
  styles : Styles,
  diagnostics : Array[String],
  background : String,
) -> Array[@layout.SectionBreak] raise @failure.Failure {
  let body = tree.child(0, "body").unwrap()
  let ends : Array[(Int, Int, Int)] = []
  let mut paragraphs = 0
  let mut tables = 0
  for id in tree.children[body] {
    let node = tree.nodes[id]
    if node.uri != word_uri {
      continue
    }
    match node.name {
      "p" => {
        paragraphs += 1
        if tree.child(id, "pPr").bind(p => tree.child(p, "sectPr"))
          is Some(section) {
          ends.push((section, paragraphs, tables))
        }
      }
      "tbl" => tables += 1
      "sdt" =>
        if tree.contents
          .values()
          .iter()
          .find_first(t => t.control == Some(id) && t.reason.is_empty())
          is Some(toc) {
          paragraphs += tree.children[tree.nodes[toc.paragraphs[0]].parent].length()
        }
      "sectPr" => {
        guard tree.children[body].last() == Some(id) else {
          @failure.reject(
            "invalid-docx", "Section properties must end the body",
          )
        }
        ends.push((id, paragraphs, tables))
      }
      _ => ()
    }
  }
  if ends.is_empty() || tree.nodes[ends.last().unwrap().0].parent != body {
    ends.push((-1, paragraphs, tables))
  }
  guard ends.length() <= 1024 else {
    @failure.reject("limit-exceeded", "Section count exceeds page budget")
  }
  let profiles : Array[@layout.SectionBreak] = []
  let headers : Map[String, Array[@layout.Paragraph]] = Map([])
  let footers : Map[String, Array[@layout.Paragraph]] = Map([])
  let identities : Map[(String, Int), Int] = Map([])
  let has_footnotes = tree.order.any(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "footnoteReference"
  })
  let note_defaults = try {
    if has_footnotes {
      Some(self.note_settings("footnote"))
    } else {
      None
    }
  } catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) => {
      diagnostics.push("unsupported-layout:notes:" + message)
      None
    }
  }
  for index, (id, _, _) in ends {
    let footnotes_at = try {
      if note_defaults is Some(defaults) {
        if id < 0 {
          defaults.position
        } else {
          defaults.read(tree, id, "footnote", document=false).position
        }
      } else {
        "pageBottom"
      }
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(message~, ..) => {
        diagnostics.push("unsupported-layout:notes:" + message)
        "pageBottom"
      }
    }
    let previous = ends.get(index - 1)
    let mut page = default_page_setup()
    let mut borders = @layout.PageBorders::new()
    let mut columns = @layout.Columns::new()
    let mut numbering = @layout.PageNumbering::new()
    let mut header_distance = 0.0
    let mut footer_distance = 0.0
    let mut kind = "nextPage"
    let mut restart = false
    let mut first = false
    let mut even = self.running_options(tree, None).1
    if id >= 0 {
      let section_diagnostics : Array[String] = []
      tree.diagnose_properties(id, self.main, section_diagnostics)
      diagnostics.append(section_diagnostics)
      let source_page = tree.page_values(id, page)
      page = {
        ..source_page,
        width: tree
        .number(id, "pgSz", "w")
        .map(page_dimension)
        .unwrap_or(page.width),
        height: tree
        .number(id, "pgSz", "h")
        .map(page_dimension)
        .unwrap_or(page.height),
      }
      columns = tree.page_columns(Some(id)) catch {
        @failure.Failure(message~, ..) => {
          diagnostics.push("unsupported-layout:columns:" + message)
          @layout.Columns::new()
        }
      }
      numbering = tree.page_numbering(Some(id)) catch {
        @failure.Failure(message~, ..) => {
          diagnostics.push("unsupported-layout:page-numbering:" + message)
          @layout.PageNumbering::new()
        }
      }
      borders = tree.page_borders(Some(id), styles.themes) catch {
        @failure.Failure(message~, ..) => {
          diagnostics.push("unsupported-layout:page-borders:" + message)
          @layout.PageBorders::new()
        }
      }
      restart = tree
        .child(id, "pgNumType")
        .bind(p => tree.nodes[p].attribute("start", uri=word_uri))
        is Some(_)
      kind = tree
        .child(id, "type")
        .bind(p => tree.nodes[p].attribute("val", uri=word_uri))
        .unwrap_or("nextPage")
      header_distance = tree
        .number(id, "pgMar", "header")
        .map(v => v / 20)
        .unwrap_or(0)
      footer_distance = tree
        .number(id, "pgMar", "footer")
        .map(v => v / 20)
        .unwrap_or(0)
      let (section_first, section_even) = self.running_options(tree, Some(id))
      first = section_first
      even = section_even
      let (current_headers, current_footers) = self.running_content(
        tree,
        id,
        styles,
        diagnostics,
        background,
        allVariants=ends.length() > 1,
      )
      for
        (name, current, inherited) in [
          ("headerReference", current_headers, headers),
          ("footerReference", current_footers, footers),
        ] {
        for variant, story in current {
          let part = self.running_part(
            tree,
            tree.children[id]
            .iter()
            .find_first(child => {
              tree.nodes[child].name == name &&
              tree.nodes[child].attribute("type", uri=word_uri) == Some(variant)
            })
            .unwrap(),
            if name == "headerReference" {
              "header"
            } else {
              "footer"
            },
          )
          inherited[variant] = if ends.length() == 1 {
            story
          } else {
            story.map(p => {
              let key = (part, p.id)
              guard identities.contains(key) || identities.length() < 32768 else {
                @failure.reject(
                  "limit-exceeded", "Section running paragraphs exceed the line budget",
                )
              }
              let identity = identities.get_or_init(key, () => {
                -500000000 - identities.length()
              })
              { ..p, id: identity, }
            })
          }
        }
      }
    }
    // ONLYOFFICE Get_SectionPageNumInfo2 adjusts the first section's starting parity.
    if index == 0 &&
      (
        (kind == "oddPage" && numbering.start % 2L == 0L) ||
        (kind == "evenPage" && numbering.start % 2L == 1L)
      ) {
      numbering = { ..numbering, start: numbering.start + 1L, }
      numbering.validate()
    }
    profiles.push({
      beforeParagraph: previous.map(e => e.1).unwrap_or(0),
      beforeTable: previous.map(e => e.2).unwrap_or(0),
      kind,
      restartNumbering: restart,
      footnotesAt: footnotes_at,
      page,
      pageBorders: borders,
      pageNumbering: numbering,
      columns,
      headers: headers.copy(),
      headerDistance: header_distance,
      footers: footers.copy(),
      footerDistance: footer_distance,
      differentFirst: first,
      differentEven: even,
    })
  }
  profiles
}
