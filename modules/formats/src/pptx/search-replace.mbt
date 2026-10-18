///|
fn search_position(
  position : Int,
  ranges : Array[(Int, Int)],
  replacement : String,
  updated : String,
) -> Int {
  let mut delta = 0
  let mut target = position
  for (start, end) in ranges {
    if position < start {
      break
    }
    if position <= end {
      target = start + delta + replacement.length()
      break
    }
    delta += replacement.length() - (end - start)
    target = position + delta
  }
  let boundaries = @layout.grapheme_boundaries(updated)
  let index = match boundaries.binary_search(target.min(updated.length())) {
    Ok(i) | Err(i) => i
  }
  boundaries[index]
}

///|
fn plain_search_changes(
  object : Object,
  ranges : Array[(Int, Int)],
  replacement : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let mut position = 0
  let mut units = 0
  for paragraph in object.paragraphs {
    let paragraph_start = position
    for run in paragraph.runs {
      let end = position + run.text.length()
      let selected = ranges.filter(r => r.0 < end && r.1 > position)
      if !selected.is_empty() && run.source is Some(source) {
        let output = StringBuilder()
        let write = fn(piece : String) raise @failure.Failure {
          units += piece.length()
          guard units <= 2097152 else {
            @failure.reject(
              "limit-exceeded", "Replacement source exceeds history budget",
            )
          }
          output.write_string(piece)
        }
        let mut cursor = 0
        for (start, finish) in selected {
          let a = (start - position).max(0)
          let b = (finish - position).min(run.text.length())
          if a > cursor {
            write(run_piece(run, cursor, a))
          }
          if start >= position && start < end {
            let prefix = source.node.qualified[:source.node.qualified.length() -
            source.node.name.length()].to_owned()
            let properties = replacement_properties(
              paragraph,
              start - paragraph_start,
              leading=true,
            )
            let markup = generated_text(replacement, prefix, properties)
            write(markup)
          }
          cursor = b
        }
        if cursor < run.text.length() {
          write(run_piece(run, cursor, run.text.length()))
        }
        let xml = output.to_string()
        changes.push({
          node: source.node.parent,
          offset: source.node.start -
          source.tree.nodes[source.node.parent].start,
          length: source.node.end - source.node.start,
          xml,
        })
      }
      position = end
    }
    position += 1
  }
  changes
}

///|
/// Recheck the query and replace one or all results in a single source transaction.
pub fn Session::replace_matches(
  self : Session,
  revision : Int,
  slide : String,
  text : String,
  options : FindOptions,
  replacement : String,
  index : Int?,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  guard @xml.valid_text(replacement) &&
    !replacement.contains("\r") &&
    replacement.length() <= 32767 else {
    @failure.reject(
      "invalid-operation", "Replacement text is invalid or excessive",
    )
  }
  let (found, truncated) = self.find_text(slide, text, options)
  if index is Some(index) {
    guard index >= 0 && index < found.length() else {
      @failure.reject("invalid-operation", "Search result index is invalid")
    }
  } else {
    guard !truncated else {
      @failure.reject(
        "limit-exceeded", "Find fewer matches before replacing all",
      )
    }
  }
  let targets : Map[String, Array[(Int, Int)]] = Map([])
  for i, item in found {
    if index is Some(index) && i != index {
      continue
    }
    guard item.reason.is_empty() else {
      @failure.reject("protected-content", item.reason)
    }
    let object = self.slides[item.slide].object(item.object)
    if object.text()[item.anchor:item.focus] == replacement {
      continue
    }
    let ranges = targets.get(item.object).unwrap_or([])
    ranges.push((item.anchor, item.focus))
    targets[item.object] = ranges
  }
  if targets.is_empty() {
    return self.query()
  }
  let slides = self.slides.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let mut bytes = 0L
  let mut after = self.selection
  let mut structural_work = 0L
  for i, original in self.slides {
    let ids = original.objects
      .filter(o => targets.contains(o.id))
      .map(o => o.id)
    if ids.is_empty() {
      continue
    }
    let plain : Array[@xml.SourceChange] = []
    let plain_ids : Array[String] = []
    let structural : Array[String] = []
    for id in ids {
      let object = original.object(id)
      let ranges = targets[id]
      let length = ranges.fold(init=object.text().length(), (length, r) => {
        length + replacement.length() - (r.1 - r.0)
      })
      guard length <= 32767 else {
        @failure.reject(
          "limit-exceeded", "Replacement frame exceeds text budget",
        )
      }
      if replacement.contains("\n") ||
        ranges.any(r => {
          paragraph_location(object, r.0).0 != paragraph_location(object, r.1).0
        }) {
        structural_work += original.tree.document.source().length().to_int64() *
          ranges.length().to_int64()
        guard structural_work <= 67108864L else {
          @failure.reject(
            "limit-exceeded", "Structural replacement work exceeds budget",
          )
        }
        structural.push(id)
      } else {
        plain.append(plain_search_changes(object, ranges, replacement))
        plain_ids.push(id)
      }
    }
    let mut candidate = original
    if !plain.is_empty() {
      let (next, edit) = self.prepare_fitted(
        candidate, plain, plain_ids, probe, profile,
      )
      bytes += edit.payload_bytes()
      guard bytes <= 4194304 else {
        @failure.reject("limit-exceeded", "Replacement history exceeds budget")
      }
      edits.push((original.tree.part, edit))
      candidate = next
    }
    // shortcut: Cross-paragraph batches reparse per match within 64 Mi units; batch joins if larger flows need them.
    for id in structural {
      let ranges = targets[id]
      for j = ranges.length() - 1; j >= 0; j = j - 1 {
        let (anchor, focus) = ranges[j]
        let selection = {
          slide: original.tree.part,
          object: id,
          objects: [id],
          mode: "text",
          anchor,
          focus,
        }
        let changes = text_changes(candidate.object(id), selection, replacement).0
        let (next, edit) = self.prepare_fitted(
          candidate,
          changes,
          [id],
          probe,
          profile,
        )
        bytes += edit.payload_bytes()
        guard bytes <= 4194304 else {
          @failure.reject(
            "limit-exceeded", "Replacement history exceeds budget",
          )
        }
        edits.push((original.tree.part, edit))
        candidate = next
      }
    }
    for id in ids {
      let target = candidate.object(id)
      if target.table is Some(_) {
        ignore(target.paint_table(probe, profile))
        continue
      }
      ignore(fit_text(target, target.geometry.unwrap(), probe, profile))
    }
    if index is Some(index) && found[index].slide == i {
      let item = found[index]
      let value = candidate.object(item.object).text()
      let focus = search_position(
        item.focus,
        targets[item.object],
        replacement,
        value,
      )
      after = {
        slide: original.tree.part,
        object: item.object,
        objects: [item.object],
        mode: "text",
        anchor: focus,
        focus,
      }
    } else if after.slide == original.tree.part &&
      after.mode == "text" &&
      targets.get(after.object) is Some(ranges) {
      let value = candidate.object(after.object).text()
      after = {
        ..after,
        anchor: search_position(after.anchor, ranges, replacement, value),
        focus: search_position(after.focus, ranges, replacement, value),
      }
    }
    slides[i] = candidate
  }
  self.commit_slides(self.main, slides, edits, after)
  self.query()
}
