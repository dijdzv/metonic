///|
pub(all) struct GetUserInput {
  id : String
} derive(Eq, Show)

///|
pub(all) struct User {
  name : String
} derive(Eq, Show)

///|
pub(all) enum GetUserError {
  NotFound
} derive(Eq, Show)

///|
pub fn get_user() -> @rpc.Procedure[GetUserInput, User, GetUserError] {
  @rpc.Procedure::new("users.get.v1")
}
