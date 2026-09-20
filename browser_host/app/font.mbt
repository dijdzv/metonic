///|
let font : @font_loader.Loader = @font_loader.create(
  "./NotoSansJP.ttf", "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f",
).unwrap()

///|
#export_name("font_fetch_cancel")
pub fn font_fetch_cancel() -> Unit {
  font.cancel()
}

///|
#export_name("font_fetch")
pub fn font_fetch() -> @font_loader.FontPromise {
  font.fetch()
}
