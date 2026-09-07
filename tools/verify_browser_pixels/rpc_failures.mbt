///|
async fn fixture_activity(host : BrowserHost, idle : Bool) -> Unit {
  for _ in 0..<300 {
    if (command(host, { "op": "fixture-active" }) == Json::number(0)) == idle {
      return
    }
    ignore(command(host, { "op": "sleep", "milliseconds": 20 }))
  }
  fail("HTTP fixture activity did not settle")
}

///|
async fn verify_rpc_failures(host : BrowserHost) -> Unit {
  ignore(command(host, { "op": "fault-route" }))
  for
    scenario in [
      ("timeout", "timeout"),
      ("slow-body", "timeout"),
      ("disconnect", "transport_error"),
      ("oversize", "response_too_large"),
      ("invalid-json", "invalid_json"),
      ("deep-json", "invalid_json"),
      ("content-type", "invalid_content_type"),
      ("protocol", "protocol:invalid_input"),
    ] {
    let (mode, error) = scenario
    ignore(
      command(host, { "op": "fill", "selector": "#rpc-user", "value": mode }),
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "RPC: " + error,
      }),
    )
    require(
      command(host, { "op": "value", "selector": "#text-input" }) ==
      Json::string("配布版 ABC 😀"),
      "HTTP failure changed browser editor",
    )
    ignore(
      command(host, {
        "op": "fill",
        "selector": "#text-input",
        "value": "再試行 ABC",
      }),
    )
    ignore(
      command(host, { "op": "fill", "selector": "#rpc-user", "value": "1" }),
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "月兎",
      }),
    )
    require(
      command(host, { "op": "value", "selector": "#text-input" }) ==
      Json::string("再試行 ABC"),
      "HTTP recovery changed browser editor",
    )
    ignore(
      command(host, {
        "op": "fill",
        "selector": "#text-input",
        "value": "配布版 ABC 😀",
      }),
    )
  }
  ignore(
    command(host, { "op": "fill", "selector": "#rpc-user", "value": "limit" }),
  )
  ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Completed",
    }),
  )
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#rpc-result",
      "text": "月兎",
    }),
  )
  fixture_activity(host, true)
  for mode in ["cancel", "replace"] {
    ignore(
      command(host, {
        "op": "fill",
        "selector": "#rpc-user",
        "value": "slow-body",
      }),
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    fixture_activity(host, false)
    if mode == "cancel" {
      ignore(command(host, { "op": "click", "selector": "#task-cancel" }))
      ignore(
        command(host, {
          "op": "wait-text",
          "selector": "#task-state",
          "text": "Canceled",
        }),
      )
    }
    ignore(
      command(host, { "op": "fill", "selector": "#rpc-user", "value": "1" }),
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#task-state",
        "text": "Completed",
      }),
    )
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "月兎",
      }),
    )
    fixture_activity(host, true)
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "月兎",
      }),
    )
    require(
      command(host, { "op": "value", "selector": "#text-input" }) ==
      Json::string("配布版 ABC 😀"),
      "late HTTP changed browser editor",
    )
  }
  ignore(command(host, { "op": "fault-route-off" }))
}
