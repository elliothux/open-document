///|
#derive(@json.FromJson)
priv struct ArchiveBudgetFields {
  fileBytes : RequestInt
  entryBytes : RequestInt
  totalBytes : RequestInt
  retainedBytes : RequestInt
  entries : RequestInt
  xmlDepth : RequestInt
  outputBytes : RequestInt
}

///|
pub struct RequestArchiveBudget {
  value : @archive.Budget
}

///|
pub extend RequestArchiveBudget with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for RequestArchiveBudget with fn from_json(input, path) {
  let fields : ArchiveBudgetFields = @json.from_json(input, path~)
  {
    value: {
      file_bytes: fields.fileBytes.value,
      entry_bytes: fields.entryBytes.value,
      total_bytes: fields.totalBytes.value,
      retained_bytes: fields.retainedBytes.value,
      entries: fields.entries.value,
      xml_depth: fields.xmlDepth.value,
      output_bytes: fields.outputBytes.value,
    },
  }
}
