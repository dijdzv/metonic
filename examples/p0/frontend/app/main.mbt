///|
fn main {
  let procedure = @api.get_user()
  let input : @api.GetUserInput = { id: "1", }
  println(procedure.id)
  println(input.id)
}
