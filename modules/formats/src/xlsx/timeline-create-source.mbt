///|
fn Session::timeline_creation_identity(
  self : Session,
  name : String,
) -> String raise @failure.Failure {
  validate_defined_name(name)
  let names : Map[String, Bool] = Map([])
  let uids : Map[String, Bool] = Map([])
  for sheet in self.sheets {
    ignore(self.read_timelines(sheet.id))
    for
      part in self.timeline_parts(
        sheet.id,
        sheet.document,
        timeline_view_extension,
        "timelineRefs",
        "timelineRef",
        "Timeline",
      ) {
      let tree = Tree::new(self.part_xml(part))
      for node in tree.timeline_children(0, "timeline") {
        let key = slicer_text(node, "name").to_upper()
        guard !names.contains(key) && names.length() < 16384 else {
          @failure.reject(
            "protected-content", "Timeline names are duplicated or exceed budget",
          )
        }
        names[key] = true
        if node.attribute(
            "uid",
            uri="http://schemas.microsoft.com/office/spreadsheetml/2016/revision10",
          )
          is Some(uid) {
          guard !uids.contains(uid.to_upper()) else {
            @failure.reject("protected-content", "Duplicate timeline view UID")
          }
          uids[uid.to_upper()] = true
        }
      }
    }
  }
  guard !names.contains(name.to_upper()) else {
    @failure.reject("invalid-name", "Timeline name is already used")
  }
  slicer_creation_uid(uids, names.length(), "00000003")
}

///|
fn timeline_cache_directory(
  workbook : @xml.Document,
  cache : Int,
  relation : String,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let uri = "{A2CB5862-8E78-49C6-8D9D-AF26E26ADB89}"
  let tree = Tree::new(workbook)
  let list = tree.one(0, "extLst")
  let extensions = list
    .map(node => {
      tree
      .all(node.id, "ext")
      .filter(node => {
        node
        .attribute("uri")
        .map(value => value.to_upper() == uri)
        .unwrap_or(false)
      })
    })
    .unwrap_or([])
  guard extensions.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate timeline cache directory")
  }
  let entry = "<odX:pivotCache xmlns:odX='\{spreadsheet_uri}' xmlns:r='\{relationship_uri[:relationship_uri.length()-1]}' cacheId='\{cache}' r:id='\{escaped_attribute(relation)}'/>"
  if extensions is [ext] {
    let parent = tree.timeline_node(ext.id, "timelineCachePivotCaches")
    guard tree.all(parent.id, "pivotCache").length() < 64 else {
      @failure.reject(
        "limit-exceeded", "Timeline date cache references exceed budget",
      )
    }
    return workbook.edit_source([insertion(parent, entry)])
  }
  let markup = "<odX:ext xmlns:odX='\{spreadsheet_uri}' uri='\{uri}'><odT:timelineCachePivotCaches xmlns:odT='\{timeline_uri}'>\{entry}</odT:timelineCachePivotCaches></odX:ext>"
  workbook.edit_source([
    insertion(
      list.unwrap_or(tree.nodes[0]),
      if list is Some(_) {
        markup
      } else {
        "<odX:extLst xmlns:odX='\{spreadsheet_uri}'>\{markup}</odX:extLst>"
      },
    ),
  ])
}

///|
fn timeline_graphic_source(
  id : String,
  name : String,
  caption : String,
  rect : @layout.Border,
) -> String raise @failure.Failure {
  let identity = escaped_attribute(name)
  let name = escaped_attribute(encoded_text(name))
  let caption = @xml.escape_text(caption)
  let graphic = "<odXdr:graphicFrame><odXdr:nvGraphicFramePr><odXdr:cNvPr id='\{id}' name='\{identity}'/><odXdr:cNvGraphicFramePr/></odXdr:nvGraphicFramePr>\{chart_transform(rect)}<odA:graphic><odA:graphicData uri='\{timeline_drawing_uri}'><odT:timeslicer xmlns:odT='\{timeline_drawing_uri}' name='\{name}'/></odA:graphicData></odA:graphic></odXdr:graphicFrame>"
  let fallback = "<odXdr:sp><odXdr:nvSpPr><odXdr:cNvPr id='0' name=''/><odXdr:cNvSpPr/></odXdr:nvSpPr><odXdr:spPr>\{picture_transform(rect)}<odA:prstGeom prst='rect'><odA:avLst/></odA:prstGeom></odXdr:spPr><odXdr:txBody><odA:bodyPr/><odA:lstStyle/><odA:p><odA:r><odA:t>\{caption}: This timeline requires Office 2013 or later.</odA:t></odA:r></odA:p></odXdr:txBody></odXdr:sp>"
  "<mc:AlternateContent xmlns:mc='\{drawing_compatibility_uri}' xmlns:odA='\{picture_drawing_uri}'><mc:Choice xmlns:a15='http://schemas.microsoft.com/office/drawing/2012/main' Requires='a15'>\{graphic}</mc:Choice><mc:Fallback>\{fallback}</mc:Fallback></mc:AlternateContent>"
}

///|
fn Session::timeline_date_members(
  self : Session,
  pivot : PivotLocation,
  field : Int,
  settings : PivotSettings,
  data : PivotCache,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Array[Double] raise @failure.Failure {
  let original = self.part_xml(pivot.cache)
  let tree = Tree::new(original)
  let fields = tree.all(tree.one(0, "cacheFields").unwrap().id, "cacheField")
  let shared = tree
    .one(fields[field].id, "sharedItems")
    .unwrap_or_else(() => {
      @failure.reject(
        "protected-content", "Timeline date cache members are unavailable",
      )
    })
  let nodes = tree.children.get(shared.id).unwrap_or([])
  guard nodes.length() == data.items[field].length() &&
    nodes.all(node => ["n", "d", "m"].contains(node.name)) else {
    @failure.reject(
      "protected-content", "Timeline source requires ordinary date or blank members",
    )
  }
  let numeric = nodes.any(node => node.name == "n")
  if numeric {
    guard !nodes.any(node => node.name == "d") else {
      @failure.reject(
        "protected-content", "Mixed native date and numeric cache members require support",
      )
    }
    let source = self.sheets[self.sheet_index(settings.sourceSheet)]
    let range = self.pivot_source(settings).0
    let mut formatted = false
    for row in (range.top + 1)..<=range.bottom {
      let address : Address = { row, column: range.left + field, }
      let calendar = [
        "yyyy-mm-dd", "mm-dd-yy", "d-mmm-yy", "d-mmm", "mmm-yy", "m/d/yy h:mm",
      ].contains(self.styles[source.style_at(address)].format)
      if source.cells.get(address.name()) is Some(cell) && cell.value != Blank {
        guard calendar else {
          @failure.reject(
            "protected-content", "Format the timeline source column as dates before insertion",
          )
        }
      }
      formatted = formatted || calendar
    }
    guard formatted else {
      @failure.reject(
        "protected-content", "Timeline source has no formatted date cells",
      )
    }
  }
  let dates : Array[Double] = []
  let changes : Array[@xml.SourceChange] = []
  for at, node in nodes {
    if data.items[field][at] is Number(value) {
      pivot_date_check(value, self.date1904)
      // shortcut: Numeric 1900 dates before March need the native/Excel leap-day mapping before conversion.
      guard !numeric || self.date1904 || value >= 61 else {
        @failure.reject(
          "protected-content", "Early 1900 numeric dates require leap-day mapping",
        )
      }
      dates.push(value)
      if node.name == "n" {
        changes.push({
          node: shared.id,
          offset: node.start - shared.start,
          length: node.end - node.start,
          xml: "<d xmlns='\{spreadsheet_uri}' v='\{pivot_date_text(value,self.date1904)}'/>",
        })
      }
    } else {
      guard data.items[field][at] == Blank else {
        @failure.reject(
          "protected-content", "Timeline cache contains non-date members",
        )
      }
    }
  }
  guard !dates.is_empty() else {
    @failure.reject("protected-content", "Timeline cache has no dates")
  }
  if numeric {
    changes.append(
      metadata_changes(shared, [
        ("containsNumber", "0"),
        ("containsDate", "1"),
        ("containsNonDate", "0"),
        ("containsInteger", "0"),
      ]),
    )
    let (document, edit) = original.edit_source(changes)
    parts[pivot.cache] = document
    edits.push((pivot.cache, edit))
  }
  dates
}
