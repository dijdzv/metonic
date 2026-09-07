///|
suberror VerifyFailure {
  VerifyFailure(String)
}

///|
fn fail(message : String) -> Unit raise Error {
  println("native semantics verification failed: " + message)
  raise VerifyFailure(message)
}

///|
fn require(condition : Bool, message : String) -> Unit raise Error {
  if !condition {
    fail(message)
  }
}

///|
fn field(object : Json, key : String) -> Json? {
  match object {
    Json::Object(values) => values.get(key)
    _ => None
  }
}

///|
fn int_field(object : Json, key : String) -> Int raise Error {
  match field(object, key) {
    Some(Json::Number(value, ..)) => value.to_int()
    _ => {
      fail("missing integer field " + key)
      0
    }
  }
}

///|
fn bool_field(object : Json, key : String) -> Bool raise Error {
  match field(object, key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => {
      fail("missing boolean field " + key)
      false
    }
  }
}

///|
fn node_field(node : Json, key : String) -> Json? {
  field(node, key)
}

///|
fn string_field(object : Json, key : String) -> String raise Error {
  match field(object, key) {
    Some(Json::String(value)) => value
    _ => {
      fail("missing string field " + key)
      ""
    }
  }
}

///|
fn node_at(nodes : Json, index : Int) -> Json raise Error {
  match nodes {
    Json::Array(values) => values[index]
    _ => {
      fail("nodes missing")
      Json::object({})
    }
  }
}

///|
fn node_with_role(nodes : Json, role : String) -> Json raise Error {
  match nodes {
    Json::Array(values) => {
      for node in values {
        if string_field(node, "role") == role {
          return node
        }
      }
      fail("missing semantic role " + role)
      Json::object({})
    }
    _ => {
      fail("nodes missing")
      Json::object({})
    }
  }
}

///|
fn array_at(value : Json, index : Int) -> Int raise Error {
  match value {
    Json::Array(values) =>
      match values[index] {
        Json::Number(number, ..) => number.to_int()
        _ => {
          fail("invalid state field")
          0
        }
      }
    _ => {
      fail("invalid state array")
      0
    }
  }
}

///|
fn check_pixels(
  response : Json,
  rgba : Bytes,
  active : Bool,
) -> Unit raise Error {
  let state = field(response, "state").unwrap()
  let width = array_at(state, 6)
  let height = array_at(state, 7)
  require(rgba.length() == width * height * 4, "capture RGBA length")
  let x0 = array_at(state, 0)
  let y0 = array_at(state, 1)
  let rw = array_at(state, 2)
  let rh = array_at(state, 3)
  let fg = if active { [242, 97, 26, 255] } else { [20, 166, 173, 255] }
  let mut i = 0
  while i < rgba.length() {
    let p = i / 4
    let x = p % width
    let y = p / width
    let expected = if x >= x0 && x < x0 + rw && y >= y0 && y < y0 + rh {
      fg
    } else {
      [5, 20, 38, 255]
    }
    let mut c = 0
    while c < 4 {
      require((rgba[i + c].to_int() - expected[c]).abs() <= 1, "capture pixel")
      c += 1
    }
    i += 4
  }
}

///|
async fn main {
  let mode = if @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1") {
    "fallback"
  } else {
    "default"
  }
  let root = @fs.realpath(".")
  let session = @fs.tmpdir(prefix="native-semantics-")
  let capture = session + "/capture.rgba"
  defer {
    if @fs.exists(capture) {
      @fs.remove(capture) catch {
        error => println("capture cleanup failed: " + error.to_string())
      }
    }
    @fs.rmdir(session) catch {
      error => println("session cleanup failed: " + error.to_string())
    }
  }
  let mut last_diagnostics = Json::object({})
  let reached : Array[Json] = []
  let config = @control.Config::new(
    root +
    "/_build/native/release/build/examples/p0/native_headless/native_headless.exe",
    [],
    capture,
    15000,
    16,
  )
  @control.with_client(config, async fn(client) {
    last_diagnostics = client.diagnostics()
    defer {
      last_diagnostics = client.diagnostics()
    }
    let snapshot = client.request("snapshot")
    let nodes = field(snapshot, "nodes")
    require(
      nodes is Some(Json::Array(values)) && values.length() == 2,
      "initial semantic nodes",
    )
    reached.push(Json::string("snapshot"))
    let button = node_at(nodes.unwrap(), 0)
    let input = node_at(nodes.unwrap(), 1)
    let revision = int_field(snapshot, "semantic_revision")
    let ref_of = (node : Json) => {
      Json::object({
        "session": node_field(node, "session").unwrap(),
        "window": node_field(node, "window").unwrap(),
        "id": node_field(node, "id").unwrap(),
        "generation": node_field(node, "generation").unwrap(),
      })
    }
    let activated = client.request(
      "semantic_activate",
      args=Json::object({
        "node": ref_of(button),
        "expected_semantic_revision": Json::number(revision.to_double()),
      }),
    )
    require(bool_field(activated, "ok"), "activate button")
    require(
      string_field(
        node_with_role(field(activated, "nodes").unwrap(), "button"),
        "value",
      ) ==
      "on",
      "button value on",
    )
    require(
      array_at(field(activated, "state").unwrap(), 4) == 1,
      "scene active",
    )
    reached.push(Json::string("activate"))
    let mut semantic_revision = int_field(activated, "semantic_revision")
    let captured = client.capture()
    require(int_field(captured.0, "frame") == 1, "first frame")
    check_pixels(captured.0, captured.1, true)
    reached.push(Json::string("capture"))
    let text = client.request(
      "semantic_set_text",
      args=Json::object({
        "node": ref_of(input),
        "text": Json::string("A😀日本"),
        "expected_semantic_revision": Json::number(
          int_field(activated, "semantic_revision").to_double(),
        ),
      }),
    )
    require(bool_field(text, "ok"), "set text")
    semantic_revision = int_field(text, "semantic_revision")
    let text_nodes = field(text, "nodes").unwrap()
    let text_input = node_with_role(text_nodes, "text_input")
    require(int_field(text_input, "selection_end") == 5, "UTF16 selection")
    reached.push(Json::string("set_text"))
    let selection = client.request(
      "semantic_set_selection",
      args=Json::object({
        "node": ref_of(input),
        "start": Json::number(1.0),
        "end": Json::number(3.0),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(bool_field(selection, "ok"), "selection")
    reached.push(Json::string("selection"))
    semantic_revision = int_field(selection, "semantic_revision")
    let invalid = client.request(
      "semantic_set_selection",
      args=Json::object({
        "node": ref_of(input),
        "start": Json::number(2.0),
        "end": Json::number(2.0),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(!bool_field(invalid, "ok"), "surrogate rejection")
    require(
      field(invalid, "error") == Some(Json::string("invalid_selection")),
      "surrogate error",
    )
    require(
      field(invalid, "nodes") == field(selection, "nodes"),
      "invalid selection state unchanged",
    )
    reached.push(Json::string("invalid_selection"))
    let focused = client.request(
      "semantic_focus",
      args=Json::object({
        "node": ref_of(input),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(bool_field(focused, "ok"), "input focus")
    semantic_revision = int_field(focused, "semantic_revision")
    let focused_button = client.request(
      "semantic_focus",
      args=Json::object({
        "node": ref_of(button),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(bool_field(focused_button, "ok"), "button focus")
    let focused_nodes = field(focused_button, "nodes").unwrap()
    require(
      bool_field(node_with_role(focused_nodes, "button"), "focused"),
      "button focused",
    )
    require(
      !bool_field(node_with_role(focused_nodes, "text_input"), "focused"),
      "input unfocused",
    )
    reached.push(Json::string("focus"))
    semantic_revision = int_field(focused_button, "semantic_revision")
    let disabled = client.request(
      "semantic_set_enabled",
      args=Json::object({
        "node": ref_of(button),
        "enabled": Json::boolean(false),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(bool_field(disabled, "ok"), "disable button")
    reached.push(Json::string("disable"))
    semantic_revision = int_field(disabled, "semantic_revision")
    let rejected = client.request(
      "semantic_activate",
      args=Json::object({
        "node": ref_of(button),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(!bool_field(rejected, "ok"), "disabled activation")
    require(
      field(rejected, "error") == Some(Json::string("disabled")),
      "disabled error",
    )
    let scene_before = field(disabled, "state")
    let frame_before = int_field(disabled, "frame")
    let nodes_before = field(disabled, "nodes")
    let ordinary = client.request("activate")
    require(!bool_field(ordinary, "ok"), "ordinary disabled activation")
    require(
      field(ordinary, "state") == scene_before &&
      int_field(ordinary, "frame") == frame_before &&
      field(ordinary, "nodes") == nodes_before,
      "disabled state unchanged",
    )
    reached.push(Json::string("disabled_noop"))
    let removed = client.request(
      "semantic_remove",
      args=Json::object({
        "node": ref_of(input),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(bool_field(removed, "ok"), "remove input")
    reached.push(Json::string("remove"))
    semantic_revision = int_field(removed, "semantic_revision")
    let recreated = client.request(
      "semantic_recreate_input",
      args=Json::object({
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(bool_field(recreated, "ok"), "recreate input")
    semantic_revision = int_field(recreated, "semantic_revision")
    let fresh_nodes = field(recreated, "nodes").unwrap()
    let fresh = node_with_role(fresh_nodes, "text_input")
    require(
      int_field(fresh, "generation") > int_field(input, "generation"),
      "generation monotonic",
    )
    reached.push(Json::string("recreate"))
    let stale = client.request(
      "semantic_focus",
      args=Json::object({
        "node": ref_of(input),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(!bool_field(stale, "ok"), "stale reference")
    require(
      field(stale, "error") == Some(Json::string("stale_target")),
      "stale error",
    )
    let cross = client.request(
      "semantic_focus",
      args=Json::object({
        "node": Json::object({
          "session": node_field(fresh, "session").unwrap(),
          "window": Json::number((int_field(fresh, "window") + 1).to_double()),
          "id": node_field(fresh, "id").unwrap(),
          "generation": node_field(fresh, "generation").unwrap(),
        }),
        "expected_semantic_revision": Json::number(
          semantic_revision.to_double(),
        ),
      }),
    )
    require(
      field(cross, "error") == Some(Json::string("stale_target")),
      "cross window error",
    )
    require(!bool_field(cross, "ok"), "cross window rejected")
    let stale_revision = client.request(
      "semantic_focus",
      args=Json::object({
        "node": ref_of(fresh),
        "expected_semantic_revision": Json::number(
          (semantic_revision - 1).to_double(),
        ),
      }),
    )
    require(
      field(stale_revision, "error") ==
      Some(Json::string("stale_semantic_revision")),
      "stale revision error",
    )
    require(!bool_field(stale_revision, "ok"), "stale revision rejected")
    reached.push(Json::string("stale_refs"))
    let result = Json::object({
      "mode": Json::string(mode),
      "checks": Json::array([
        Json::string("semantic actions and UTF16 selection"),
      ]),
      "reached": Json::array(reached),
      "adapter": client.diagnostics(),
    })
    if !@fs.exists(".work/native-semantics") {
      @fs.mkdir(".work/native-semantics", recursive=true)
    }
    @fs.write_file(
      ".work/native-semantics/" + mode + ".json",
      result.stringify(),
    )
    client.close()
    println(result.stringify())
  }) catch {
    error => {
      try {
        if !@fs.exists(".work/native-semantics") {
          @fs.mkdir(".work/native-semantics", recursive=true)
        }
        let failure = Json::object({
          "mode": Json::string(mode),
          "ok": Json::boolean(false),
          "error": Json::string(error.to_string()),
          "reached": Json::array(reached),
          "adapter": last_diagnostics,
        })
        @fs.write_file(
          ".work/native-semantics/" + mode + ".json",
          failure.stringify(),
        )
      } catch {
        write_error =>
          println("failure result write failed: " + write_error.to_string())
      }
      abort(error.to_string())
    }
  }
}
