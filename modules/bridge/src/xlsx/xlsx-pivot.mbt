///|
priv struct PivotSettingsFields {
  sourceSheet : String
  source : String
  rows : Array[@common.RequestInt]
  columns : Array[@common.RequestInt]
  filters : Array[PivotFilterRequest]
  subtotals : Array[@common.RequestInt]
  numberGroups : Array[PivotNumberGroupRequest]
  dateGroups : Array[PivotDateGroupRequest]
  values : Array[PivotValueRequest]
} derive(@json.FromJson)

///|
priv struct PivotFilterRequest {
  field : @common.RequestInt
  report : Bool
  values : @common.RequiredNullable[Array[CellValueRequest]]
} derive(@json.FromJson)

///|
priv struct PivotDateGroupRequest {
  field : @common.RequestInt
  units : Array[String]
} derive(@json.FromJson)

///|
priv struct PivotNumberGroupRequest {
  field : @common.RequestInt
  start : @common.RequiredNullable[@common.RequestNumber]
  end : @common.RequiredNullable[@common.RequestNumber]
  interval : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct PivotValueRequest {
  field : @common.RequestInt
  aggregate : String
  name : String
  showDataAs : String
  baseField : @common.RequiredNullable[@common.RequestInt]
  baseItem : Json
} derive(@json.FromJson)

///|
priv struct PivotSettingsRequest {
  value : @model.PivotSettings
}

///|
fn pivot_axis_field(
  field : @common.RequestInt,
  path : @json.JsonPath,
) -> Int32 raise @json.JsonDecodeError {
  guard field.value < @model.PivotSourceColumns else {
    raise @json.JsonDecodeError((path, "Invalid pivot axis field"))
  }
  field.value
}

///|
impl @json.FromJson for PivotSettingsRequest with fn from_json(input, path) {
  guard input is Object(fields) &&
    fields.length() == 9 &&
    input
    is {
      "rows": Array(rows),
      "columns": Array(columns),
      "filters": Array(filters),
      "subtotals": Array(subtotals),
      "numberGroups": Array(groups),
      "dateGroups": Array(dates),
      "values": Array(values),
      ..
    } &&
    rows.length() > 0 &&
    rows.length() <= @model.PivotFieldsPerRole &&
    columns.length() <= @model.PivotFieldsPerRole &&
    filters.length() <= @model.PivotFieldsPerRole &&
    subtotals.length() <= @model.PivotSubtotalFields &&
    groups.length() <= @model.PivotGroupUnits &&
    dates.length() + groups.length() <= @model.PivotGroupUnits &&
    values.length() > 0 &&
    values.length() <= @model.PivotFieldsPerRole else {
    raise @json.JsonDecodeError((path, "Invalid pivot settings"))
  }
  // Bound collections before decoding their members into typed records.
  for group in dates {
    guard group is Object(fields) &&
      fields.length() == 2 &&
      group is { "units": Array(units), .. } &&
      units.length() > 0 &&
      units.length() <= @model.PivotDateUnits else {
      raise @json.JsonDecodeError((path, "Invalid pivot calendar group"))
    }
  }
  for group in groups {
    guard group is Object(fields) && fields.length() == 4 else {
      raise @json.JsonDecodeError((path, "Invalid pivot numeric group"))
    }
  }
  for filter in filters {
    guard filter is Object(fields) &&
      fields.length() == 3 &&
      (
        filter is { "values": Null, .. } ||
        (
          filter is { "values": Array(members), .. } &&
          members.length() <= @model.PivotMembers
        )
      ) else {
      raise @json.JsonDecodeError((path, "Invalid pivot report filter"))
    }
  }
  for value in values {
    guard value is Object(fields) && fields.length() == 6 else {
      raise @json.JsonDecodeError((path, "Invalid pivot value field"))
    }
  }
  let request : PivotSettingsFields = @json.from_json(input, path~)
  let value : @model.PivotSettings = {
    sourceSheet: request.sourceSheet,
    source: request.source,
    dateGroups: request.dateGroups.map(group => {
      field: group.field.value,
      units: group.units,
    }),
    numberGroups: request.numberGroups.map(group => {
      field: group.field.value,
      start: group.start.value.map(number => number.value),
      end: group.end.value.map(number => number.value),
      interval: group.interval.value,
    }),
    subtotals: request.subtotals.map(field => pivot_axis_field(field, path)),
    rows: request.rows.map(field => pivot_axis_field(field, path)),
    columns: request.columns.map(field => pivot_axis_field(field, path)),
    filters: request.filters.map(filter => {
      field: filter.field.value,
      report: filter.report,
      values: filter.values.value.map(members => members.map(item => item.value)),
    }),
    values: request.values.map(value => {
      let baseItem = match value.baseItem {
        Null => None
        String("previous") => Some(@model.PivotBaseItem::Previous)
        String("next") => Some(@model.PivotBaseItem::Next)
        item => {
          let cell : CellValueRequest = @json.from_json(item, path~)
          Some(@model.PivotBaseItem::Member(cell.value))
        }
      }
      @model.PivotValue::{
        field: value.field.value,
        aggregate: value.aggregate,
        showDataAs: value.showDataAs,
        baseField: value.baseField.value.map(field => field.value),
        baseItem,
        name: value.name,
      }
    }),
  }
  { value, }
}

///|
priv struct TimelineEndpointRequest {
  name : String
  handle : @common.RequestInt
  level : @common.RequestInt
  position : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct TimelineLevelRequest {
  name : String
  level : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct TimelineScrollRequest {
  name : String
  level : @common.RequestInt
  position : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct TimelineRangeRequest {
  start : String
  end : String
} derive(@json.FromJson)

///|
priv struct TimelineFilterRequest {
  name : String
  range : @common.RequiredNullable[TimelineRangeRequest]
} derive(@json.FromJson)

///|
priv struct SlicerScrollRequest {
  layout : @common.RequestInt
  id : String
  position : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct SlicerSelectionRequest {
  layout : @common.RequestInt
  id : String
  index : @common.RequiredNullable[@common.RequestInt]
  additive : Bool
} derive(@json.FromJson)

///|
priv struct SlicerFilterRequest {
  name : String
  indices : Array[@common.RequestInt]
} derive(@json.FromJson)

///|
priv struct PivotSourceRevisionRequest {
  sourceRevision : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct PivotCreateRequest {
  name : String
  destination : String
  settings : PivotSettingsRequest
} derive(@json.FromJson)

///|
priv struct PivotUpdateRequest {
  part : String
  settings : PivotSettingsRequest
} derive(@json.FromJson)

///|
priv struct PivotPartRequest {
  part : String
} derive(@json.FromJson)

///|
fn slicer_member_index(
  value : @common.RequestInt,
) -> Int32 raise @failure.Failure {
  guard value.value < @model.SlicerMembers else {
    @failure.reject("invalid-operation", "Invalid slicer member index")
  }
  value.value
}

///|
fn xlsx_pivot_edit(
  session : @model.Session,
  revision : Int32,
  sheet : String,
  action : String,
  change : Json,
) -> Json raise @failure.Failure {
  guard change is Object(fields) && fields.contains("action") else {
    @failure.reject("invalid-operation", "Invalid analysis command")
  }
  match action {
    "setTimelineEndpoint" if fields.length() == 5 => {
      let input : TimelineEndpointRequest = @common.request(change)
      session.set_timeline_endpoint(
        revision,
        sheet,
        input.name,
        input.handle.value,
        input.level.value,
        input.position.value,
      )
    }
    "setTimelineLevel" if fields.length() == 3 => {
      let input : TimelineLevelRequest = @common.request(change)
      session.set_timeline_level(revision, sheet, input.name, input.level.value)
    }
    "scrollTimeline" if fields.length() == 4 => {
      let input : TimelineScrollRequest = @common.request(change)
      session.scroll_timeline(
        revision,
        sheet,
        input.name,
        input.level.value,
        input.position.value,
      )
    }
    "filterTimeline" if fields.length() == 3 => {
      guard fields.get("range") is Some(Null) ||
        (fields.get("range") is Some(Object(range)) && range.length() == 2) else {
        @failure.reject("invalid-operation", "Invalid timeline range")
      }
      let input : TimelineFilterRequest = @common.request(change)
      let range = input.range.value.map(range => (range.start, range.end))
      session.filter_timeline(revision, sheet, input.name, range)
    }
    "deleteSlicer" | "deleteTimeline" if fields.length() == 2 => {
      let input : SheetRenameRequest = @common.request(change)
      if action == "deleteTimeline" {
        session.delete_timeline(revision, sheet, input.name)
      } else {
        session.delete_slicer(revision, sheet, input.name)
      }
    }
    "scrollSlicer" if fields.length() == 4 => {
      let input : SlicerScrollRequest = @common.request(change)
      session.scroll_slicer(
        revision,
        sheet,
        input.layout.value,
        input.id,
        slicer_member_index(input.position),
      )
    }
    "selectSlicer" if fields.length() == 5 => {
      let input : SlicerSelectionRequest = @common.request(change)
      let index = match input.index.value {
        Some(value) => Some(slicer_member_index(value))
        None => None
      }
      session.select_slicer(
        revision,
        sheet,
        input.layout.value,
        input.id,
        index,
        input.additive,
      )
    }
    "filterSlicer" if fields.length() == 3 &&
      fields.get("indices") is Some(Array(indices)) &&
      !indices.is_empty() &&
      indices.length() <= @model.SlicerMembers => {
      let input : SlicerFilterRequest = @common.request(change)
      session.filter_slicer(
        revision,
        sheet,
        input.name,
        input.indices.map(slicer_member_index),
      )
    }
    "createPivot" | "updatePivot" => {
      let keys = if action == "createPivot" {
        ["action", "name", "destination", "settings", "sourceRevision"]
      } else {
        ["action", "part", "settings", "sourceRevision"]
      }
      guard fields.length() == keys.length() &&
        fields.keys().all(key => keys.contains(key)) else {
        @failure.reject("invalid-operation", "Invalid pivot command")
      }
      let preview : PivotSourceRevisionRequest = @common.request(change)
      guard preview.sourceRevision.value == revision else {
        @failure.reject(
          "stale-revision", "Preview the current source before changing a pivot",
        )
      }
      if action == "createPivot" {
        let input : PivotCreateRequest = @common.request(change)
        ignore(
          session.create_pivot(
            revision,
            sheet,
            input.name,
            input.destination,
            input.settings.value,
          ),
        )
      } else {
        let input : PivotUpdateRequest = @common.request(change)
        ignore(
          session.update_pivot(
            revision,
            sheet,
            input.part,
            input.settings.value,
          ),
        )
      }
      session.query(sheet=Some(sheet))
    }
    "deletePivot" | "refreshPivot" if fields.length() == 2 => {
      let input : PivotPartRequest = @common.request(change)
      if action == "deletePivot" {
        ignore(session.delete_pivot(revision, sheet, input.part))
      } else {
        ignore(session.refresh_pivot(revision, sheet, input.part))
      }
      session.query(sheet=Some(sheet))
    }
    _ => @failure.reject("invalid-operation", "Invalid analysis command")
  }
}
