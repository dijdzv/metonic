///|
// The pinned parser has no non-deprecated depth-limit parameter; omitting it
// would restore the much larger default at the transport boundary.
#warnings("-deprecated")
pub fn parse_bounded(text : String) -> Json raise @codec.ParseError {
  @codec.parse(text, max_nesting_depth=32)
}
