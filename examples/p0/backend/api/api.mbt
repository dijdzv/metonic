///|
pub(all) struct GetUserInput {
  id : String
} derive(Eq, Debug)

///|
pub(all) struct User {
  name : String
} derive(Eq, Debug)

///|
pub(all) enum GetUserError {
  NotFound
} derive(Eq, Debug)

///|
pub fn get_user() -> @rpc.Procedure[GetUserInput, User, GetUserError] {
  @rpc.Procedure::new("users.get.v1")
}
