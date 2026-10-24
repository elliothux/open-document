///|
fn Session::import_table_styles(
  self : Session,
  source : Session,
  document : @xml.Document,
  remap : Map[String, String],
  first : Int64,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> (@xml.Document, Int64) raise @failure.Failure {
  let tables = document
    .nodes()
    .filter(n => n.uri == drawing_uri && n.name == "tbl")
  if tables.is_empty() {
    return (document, first)
  }
  let source_book = read_table_styles(
    source.opc,
    source.main,
    source.cache,
    source.parts,
  )
  let tree = Tree::new("imported-slide", document)
  let changes = []
  let mut next = first
  for table in tables {
    let props = tree.one(table.id, "tblPr")
    let field = props.bind(p => tree.one(p.id, "tableStyleId"))
    let id = field
      .map(n => n.text.trim().to_owned().to_upper())
      .unwrap_or(source_book.default_id)
    let target = match remap.get(id) {
      Some(id) => id
      None => {
        let book = read_table_styles(self.opc, self.main, self.cache, parts)
        while book.styles.contains(document_guid(next)) ||
              remap.values().any(id => id == document_guid(next)) {
          next += 1L
        }
        guard next <= 4294967295L else {
          @failure.reject(
            "limit-exceeded", "Imported table style identities exhausted",
          )
        }
        let target = document_guid(next)
        next += 1L
        let markup = if id.is_empty() {
          "<a:tblStyle xmlns:a='\{drawing_uri}' styleId='\{target}' styleName='Imported default'><a:wholeTbl/></a:tblStyle>"
        } else {
          guard source_book.styles.get(id) is Some(style) else {
            @failure.reject(
              "protected-content", "Imported table style is unresolved",
            )
          }
          let (updated, _) = style.tree.document.edit_source([
            attribute_change(style, "styleId", target),
          ])
          style.tree.standalone_markup(updated, style.node.id)
        }
        let definition = @xml.Document::parse(
          @utf8.encode(markup),
          "imported-table-style",
          self.budget.xml_depth,
          self.budget.entry_bytes,
        )
        let style = Tree::new("imported-table-style", definition)
        self.table_style_resource(
          {
            ..book,
            styles: Map([
              (target, { tree: style, node: definition.nodes()[0], }),
            ]),
          },
          target,
          parts,
          created,
          edits,
        )
        remap[id] = target
        target
      }
    }
    let markup = "<a:tableStyleId xmlns:a='\{drawing_uri}'>\{target}</a:tableStyleId>"
    changes.push(
      match (props, field) {
        (_, Some(field)) =>
          clipboard_source_change({ tree, node: field, }, markup)
        (Some(props), None) => insertion(props, markup)
        (None, None) =>
          @xml.SourceChange::{
            node: table.id,
            offset: table.opening_end - table.start,
            length: 0,
            xml: "<a:tblPr xmlns:a='\{drawing_uri}'>\{markup}</a:tblPr>",
          }
      },
    )
  }
  (document.edit_source(changes).0, next)
}
