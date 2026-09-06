///|
pub fn get_user(
  input : @api.GetUserInput,
) -> Result[@api.User, @api.GetUserError] {
  if input.id == "1" {
    Ok({ name: "月兎" })
  } else {
    Err(@api.NotFound)
  }
}

///|
pub fn binding() -> @rpc.Binding[
  @api.GetUserInput,
  @api.User,
  @api.GetUserError,
] {
  @rpc.bind(@api.get_user(), get_user)
}
