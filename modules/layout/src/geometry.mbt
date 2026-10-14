///|
pub(all) struct Matrix {
  a : Double
  b : Double
  c : Double
  d : Double
  e : Double
  f : Double
} derive(ToJson)

///|
pub extend Matrix with ToJson::{to_json}

///|
pub fn Matrix::identity() -> Matrix {
  { a: 1, b: 0, c: 0, d: 1, e: 0, f: 0, }
}

///|
pub fn Matrix::then(self : Matrix, inner : Matrix) -> Matrix {
  {
    a: self.a * inner.a + self.c * inner.b,
    b: self.b * inner.a + self.d * inner.b,
    c: self.a * inner.c + self.c * inner.d,
    d: self.b * inner.c + self.d * inner.d,
    e: self.a * inner.e + self.c * inner.f + self.e,
    f: self.b * inner.e + self.d * inner.f + self.f,
  }
}

///|
pub fn Matrix::point(self : Matrix, x : Double, y : Double) -> (Double, Double) {
  (self.a * x + self.c * y + self.e, self.b * x + self.d * y + self.f)
}

///|
pub fn Matrix::inverse(self : Matrix) -> Matrix raise @failure.Failure {
  guard [self.a, self.b, self.c, self.d, self.e, self.f].all(value => {
    !value.is_nan() && !value.is_inf() && value.abs() <= 1000000000
  }) else {
    @failure.reject(
      "invalid-transform", "Transform exceeds finite coordinate budget",
    )
  }
  let determinant = self.a * self.d - self.b * self.c
  guard determinant.abs() >= 0.000000001 &&
    !determinant.is_nan() &&
    !determinant.is_inf() else {
    @failure.reject("invalid-transform", "Noninvertible object transform")
  }
  {
    a: self.d / determinant,
    b: -self.b / determinant,
    c: -self.c / determinant,
    d: self.a / determinant,
    e: (self.c * self.f - self.d * self.e) / determinant,
    f: (self.b * self.e - self.a * self.f) / determinant,
  }
}

///|
pub(all) enum PathSegment {
  Move(Double, Double)
  Line(Double, Double)
  Cubic(Double, Double, Double, Double, Double, Double)
  Close
}

///|
pub impl ToJson for PathSegment with fn to_json(self) {
  match self {
    Move(x, y) => { "op": "move", "x": x, "y": y }
    Line(x, y) => { "op": "line", "x": x, "y": y }
    Cubic(x1, y1, x2, y2, x, y) =>
      { "op": "cubic", "x1": x1, "y1": y1, "x2": x2, "y2": y2, "x": x, "y": y }
    Close => { "op": "close" }
  }
}

///|
pub extend PathSegment with ToJson::{to_json}
