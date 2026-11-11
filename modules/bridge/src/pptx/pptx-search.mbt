///|
priv struct SearchOptionsRequest {
  matchCase : Bool?
  wholeWord : Bool?
  all : Bool?
} derive(@json.FromJson)

///|
priv struct FindRequest {
  revision : @common.RequestInt
  slide : String
  text : String
  options : FindOptionsRequest
} derive(@json.FromJson)

///|
priv struct ReplaceMatchesRequest {
  revision : @common.RequestInt
  slide : String
  text : String
  options : FindOptionsRequest
  replacement : String
  index : @common.RequiredNullable[@common.RequestInt]?
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct FindOptionsRequest {
  value : @model.FindOptions
}

///|
impl @json.FromJson for FindOptionsRequest with fn from_json(input, path) {
  guard input is Object(fields) &&
    fields.keys().all(key => ["matchCase", "wholeWord", "all"].contains(key)) else {
    raise @json.JsonDecodeError((path, "Invalid presentation search options"))
  }
  let options : SearchOptionsRequest = @json.from_json(input, path~)
  {
    value: @model.FindOptions::new(
      matchCase=options.matchCase.unwrap_or(false),
      wholeWord=options.wholeWord.unwrap_or(false),
      all=options.all.unwrap_or(true),
    ),
  }
}

///|
let search_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "findPptx": (_context, session, input) => {
    let command : FindRequest = @common.request(input)
    session.find(
      command.revision.value,
      command.slide,
      command.text,
      command.options.value,
    )
  },
  "replacePptxMatches": (context, session, input) => {
    let command : ReplaceMatchesRequest = @common.request(input)
    let index = command.index
      .bind(value => value.value)
      .map(value => value.value)
    session.replace_matches(
      command.revision.value,
      command.slide,
      command.text,
      command.options.value,
      command.replacement,
      index,
      context.probe,
      command.profile.value,
    )
  },
}
