///|
fn paragraph_gap_key(gap : ParagraphGap) -> Json {
  match gap {
    Points(value) => { "points": value }
    Percent(value) => { "percent": value }
  }
}

///|
fn Object::fit_key(self : Object) -> Json {
  {
    "size": self.geometry.map(g => [g.width, g.height]),
    "body": [self.body.left, self.body.top, self.body.right, self.body.bottom],
    "wrap": self.body.wrap,
    "fit": self.body.fit,
    "paragraphs": self.paragraphs.map(p => {
      let value : Json = {
        "before": paragraph_gap_key(p.before),
        "after": paragraph_gap_key(p.after),
        "spacing": p.spacing,
        "left": p.left,
        "right": p.right,
        "first": p.first,
        "align": p.align,
        "rtl": p.rtl,
        "tabs": p.tabs,
        "defaultTab": p.default_tab,
        "bullet": p.bullet,
        "bulletStyle": p.bullet_style,
        "runs": p.runs.map(run => run.parts),
      }
      value
    }),
  }
}

///|
fn check_changed_source_fonts(
  before : Slide,
  after : Slide,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
) -> Unit raise @failure.Failure {
  let previous = slide_font_keys([before])
  for key in slide_font_keys([after]) {
    if previous.contains(key) {
      continue
    }
    guard probe is Some(probe) &&
      @layout.font_profile_identity(profile, key) is Some(identity) else {
      @failure.reject("missing-font", "Missing source font profile: " + key)
    }
    ignore(probe.font_index(identity))
  }
}

///|
fn Session::reflow_source(
  self : Session,
  slides : Array[Slide],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  original~ : Array[Slide] = self.slides,
) -> Array[Slide] raise @failure.Failure {
  let candidates = slides.mapi((index, slide) => {
    read_slide(
      self.opc,
      self.main,
      self.cache,
      slide.tree,
      index=if slide.tree.document.nodes()[0].name == "sld" {
        index
      } else {
        self.source_index(slide.tree.part)
      },
      parts~,
      date_time=self.date_time,
    )
  })
  let updates : Map[String, (Tree, Array[@xml.SourceChange])] = Map([])
  for i, slide in candidates {
    let before = original[i]
    check_changed_source_fonts(before, slide, probe, profile)
    guard slide.diagnostics.all(message => before.diagnostics.contains(message)) &&
      slide.objects.all(object => {
        object.geometry is Some(_) ||
        before.objects
        .iter()
        .find_first(old => old.id == object.id)
        .map(old => old.geometry is None)
        .unwrap_or(false)
      }) else {
      @failure.reject(
        "protected-content", "Source edit introduces unsupported content or unresolved page geometry",
      )
    }
    for object in slide.objects {
      if slide.tree.document.nodes()[0].name != "sld" &&
        object.source.tree.part != slide.tree.part {
        continue
      }
      if object.body.fit == "none" || object.paragraphs.is_empty() {
        continue
      }
      let previous = before.objects
        .iter()
        .find_first(before => before.id == object.id)
      if previous
        .map(before => before.fit_key() == object.fit_key())
        .unwrap_or(false) {
        continue
      }
      guard probe is Some(probe) else {
        @failure.reject(
          "missing-font", "Source text reflow requires a font probe and profile",
        )
      }
      for key in slide_font_keys([{ ..slide, objects: [object], }]) {
        guard @layout.font_profile_identity(profile, key) is Some(identity) else {
          @failure.reject("missing-font", "Missing source font profile: " + key)
        }
        ignore(probe.font_index(identity))
      }
      let changes = derived_frame_changes(object, probe, profile)
      if changes.is_empty() {
        continue
      }
      let entry = updates.get_or_init(object.source.tree.part, () => {
        (object.source.tree, [])
      })
      for change in changes {
        let same = entry.1
          .iter()
          .find_first(other => {
            other.node == change.node &&
            other.offset == change.offset &&
            other.length == change.length
          })
        if same is Some(same) {
          guard same.xml == change.xml else {
            @failure.reject(
              "protected-content", "Shared source text frames require different sizes",
            )
          }
        } else {
          entry.1.push(change)
        }
      }
    }
  }
  let documents : Map[String, @xml.Document] = Map([])
  for part, (tree, changes) in updates {
    let (document, edit) = tree.document.edit_source(changes)
    documents[part] = document
    if !self.slides.any(slide => slide.tree.part == part) {
      parts[part] = document
    }
    edits.push((part, edit))
  }
  candidates.mapi((index, slide) => {
    read_slide(
      self.opc,
      self.main,
      self.cache,
      documents
      .get(slide.tree.part)
      .map(document => Tree::new(slide.tree.part, document))
      .unwrap_or(slide.tree),
      index=if slide.tree.document.nodes()[0].name == "sld" {
        index
      } else {
        self.source_index(slide.tree.part)
      },
      parts~,
      date_time=self.date_time,
    )
  })
}
