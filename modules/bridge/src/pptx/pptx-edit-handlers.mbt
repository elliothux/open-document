///|
priv struct SlideEditRequest {
  revision : @common.RequestInt
  slide : String
  change : Json
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct ObjectEditRequest {
  revision : @common.RequestInt
  change : Json
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct SelectRequest {
  revision : @common.RequestInt
  slide : String
  object : String
  mode : String
  anchor : @common.RequestInt
  focus : @common.RequestInt
  objects : ObjectSelectionRequest
} derive(@json.FromJson)

///|
priv struct ReplaceRequest {
  revision : @common.RequestInt
  text : String
  profile : @common.RequestProfile
  candidateId : @common.RequestInt?
} derive(@json.FromJson)

///|
priv struct DeleteRequest {
  revision : @common.RequestInt
  backward : Bool
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct DateTimeRequest {
  revision : @common.RequestInt
  dateTime : String
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct FragmentRequest {
  revision : @common.RequestInt
  fragment : String
} derive(@json.FromJson)

///|
priv struct PasteRequest {
  revision : @common.RequestInt
  fragment : String
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
let edit_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "editPptxSlides": (context, session, input) => {
    let command : SlideEditRequest = @common.request(input)
    session.edit_slides(
      command.revision.value,
      command.slide,
      pptx_slide_edit(command.change),
      probe=context.probe,
      profile=command.profile.value,
    )
  },
  "editPptxObjects": (context, session, input) => {
    let command : ObjectEditRequest = @common.request(input)
    session.edit_objects(
      command.revision.value,
      pptx_object_edit(command.change),
      context.probe,
      command.profile.value,
    )
  },
  "selectPptx": (_context, session, input) => {
    let command : SelectRequest = @common.request(input)
    session.select(
      command.revision.value,
      command.slide,
      command.object,
      command.mode,
      command.anchor.value,
      command.focus.value,
      objects=Some(command.objects.identities()),
    )
  },
  "replacePptx": (context, session, input) => {
    let command : ReplaceRequest = @common.request(input)
    session.replace(
      command.revision.value,
      command.text,
      context.probe,
      command.profile.value,
      candidate_id=command.candidateId.map(value => value.value),
    )
  },
  "deletePptx": (context, session, input) => {
    let command : DeleteRequest = @common.request(input)
    session.delete(
      command.revision.value,
      command.backward,
      context.probe,
      command.profile.value,
    )
  },
  "undoPptx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.undo(revision)
  },
  "redoPptx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.undo(revision, redo=true)
  },
  "dateTimePptx": (context, session, input) => {
    let command : DateTimeRequest = @common.request(input)
    session.set_date_time(
      command.revision.value,
      command.dateTime,
      context.probe,
      command.profile.value,
    )
  },
  "followPptxHyperlink": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.follow_hyperlink(revision)
  },
  "copyPptx": (_context, session, input) => {
    let revision = @common.request_revision(input)
    session.copy(revision)
  },
  "pastePptxFragment": (context, session, input) => {
    let command : PasteRequest = @common.request(input)
    session.paste_text_fragment(
      command.revision.value,
      command.fragment,
      context.probe,
      command.profile.value,
    )
  },
  "pastePptxObjects": (context, session, input) => {
    let command : PasteRequest = @common.request(input)
    session.paste_object_fragment(
      command.revision.value,
      command.fragment,
      context.probe,
      command.profile.value,
    )
  },
  "objectFragmentImagesPptx": (context, session, input) => {
    let command : FragmentRequest = @common.request(input)
    let images = session.object_fragment_images(
      command.revision.value,
      command.fragment,
    )
    if input is { "prepareImages": True, .. } {
      Json(
        images.map(bytes => @common.image_response(context.output, bytes, None)),
      )
    } else {
      Json(images.map(bytes => context.output.add(bytes)))
    }
  },
  "objectFragmentMediaPptx": (context, session, input) => {
    let command : FragmentRequest = @common.request(input)
    Json(
      session.object_fragment_media(command.revision.value, command.fragment, encode_media=bytes => {
        Json(context.output.add(bytes))
      }),
    )
  },
  "objectFragmentResourcesPptx": (context, session, input) => {
    let command : FragmentRequest = @common.request(input)
    let verify = if input is { "verifyImages": True, .. } {
      Some(@model.verifies_upload_raster)
    } else {
      None
    }
    session.object_fragment_resources(
      command.revision.value,
      command.fragment,
      bytes => @common.image_response(context.output, bytes, None, verify?),
      bytes => Json(context.output.add(bytes)),
    )
  },
}
