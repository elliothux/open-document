///|
fn formula_random(seed : Bytes?) -> @random.Rand? raise @failure.Failure {
  let seed = match seed {
    Some(_) => seed
    None => @env.rand(32)
  }
  guard seed is Some(seed) else { return None }
  guard seed.length() == 32 else {
    @failure.reject(
      "invalid-operation", "Formula random seed must contain 32 bytes",
    )
  }
  Some(@random.Rand::chacha8(seed~))
}

///|
fn Expression::contains_rand(self : Expression) -> Bool {
  match self {
    Function("RAND", _) => true
    Function(_, args) => args.any(arg => arg.contains_rand())
    Unary(_, value) => value.contains_rand()
    Binary(_, left, right) => left.contains_rand() || right.contains_rand()
    _ => false
  }
}

///|
fn Calculation::random_values(
  self : Calculation,
) -> Map[(Int32, Address), (Value, String?)] {
  let result = Map([])
  for (sheet, address), expression in self.expressions {
    guard expression.contains_rand() else { continue }
    let key = (sheet, address)
    if self.values.get(key) is Some(value) {
      result[key] = (value, self.hyperlinks.get(key).bind(target => target))
    }
  }
  result
}

///|
fn random_history_bytes(
  values : Map[(Int32, Address), (Value, String?)],
) -> Int64 raise @failure.Failure {
  values
  .iter()
  .fold(init=0L, (sum, item) => {
    sum +
    64 +
    2 *
    (
      item.0.1.name().length().to_int64() +
      item.1.0.display().length().to_int64() +
      item.1.1.map(target => target.length().to_int64()).unwrap_or(0)
    )
  })
}
