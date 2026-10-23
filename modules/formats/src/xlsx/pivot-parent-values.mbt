///|
fn PivotCache::add_parent_values(
  self : PivotCache,
  settings : PivotSettings,
  record : Array[Int],
  rows : Array[Array[Int]],
  columns : Array[Array[Int]],
  parents : Map[String, Array[PivotStatistic]],
  directions : (Bool, Bool),
  work : Int,
) -> Int raise @failure.Failure {
  let keys : Map[String, Bool] = Map([])
  if directions.0 {
    for row in rows {
      for column in columns + [[]] {
        keys[Json((row[:row.length() - 1].to_owned(), column)).stringify()] = true
      }
    }
  }
  if directions.1 {
    for column in columns {
      if column.is_empty() {
        continue
      }
      for row in rows + [[]] {
        keys[Json((row, column[:column.length() - 1].to_owned())).stringify()] = true
      }
    }
  }
  let mut work = work
  for key in keys.keys() {
    work += settings.values.length()
    guard work <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Pivot parent aggregation exceeds work budget",
      )
    }
    let statistics = match parents.get(key) {
      Some(statistics) => statistics
      None => {
        guard (parents.length() + 1) * settings.values.length() <= 32768 else {
          @failure.reject(
            "limit-exceeded", "Pivot parent aggregates exceed value budget",
          )
        }
        let statistics = settings.values.map(_ => PivotStatistic::new())
        parents[key] = statistics
        statistics
      }
    }
    for at, field in settings.values {
      statistics[at].add(self.items[field.field][record[field.field]])
    }
  }
  work
}
