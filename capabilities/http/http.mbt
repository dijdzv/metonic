///|
pub(all) struct Request {
  path : String
  content_type : String
  body : Bytes
  response_limit : Int
  accepted_content_types : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct Response {
  status : Int
  content_type : String?
  body : Bytes
} derive(Eq, Debug)

///|
pub(all) enum Failure {
  InvalidRequest
  Transport
  ResponseTooLarge
  InvalidContentType
  Timeout
} derive(Eq, Debug)

///|
/// A bounded POST exchange. Adapters own the endpoint and resource cleanup.
/// Cancellation propagates through async, never through Failure.
pub(open) trait Http {
  async fn post(Self, Request) -> Result[Response, Failure]
}
