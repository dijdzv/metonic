///|
fn verify_input_lifetime(observation : Json, target : String) -> Unit raise {
  require(
    string_field(observation, "text") ==
    "PASS production_input_owner both_fields composition selection stop restart pending_frames" &&
    int_field(observation, "errors") == 0,
    "input lifetime probe failed " + target + ": " + observation.stringify(),
  )
}
