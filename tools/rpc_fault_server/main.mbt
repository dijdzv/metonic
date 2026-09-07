///|
struct Input {
  id : String
} derive(FromJson)

///|
struct Request {
  input : Input
} derive(FromJson)

///|
async fn main {
  let endpoint = @wire.endpoint(@handlers.binding(), error => {
    match error {
      NotFound => "not_found"
    }
  })
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let active = Ref(0)
  println("RPC_FAULT_READY " + server.addr.to_string())
  server.run_forever(
    (request, body, conn) => {
      defer conn.close()
      let headers : Map[@http.CaseInsensitiveString, String] = Map([])
      headers.set(@http.CaseInsensitiveString("Connection"), "close")
      headers.set(
        @http.CaseInsensitiveString("Content-Type"),
        "application/json",
      )
      headers.set(
        @http.CaseInsensitiveString("Access-Control-Allow-Origin"),
        "*",
      )
      headers.set(
        @http.CaseInsensitiveString("Access-Control-Allow-Headers"),
        "content-type",
      )
      headers.set(
        @http.CaseInsensitiveString("Access-Control-Allow-Methods"),
        "POST, GET, OPTIONS",
      )
      if request.meth == @http.Options {
        conn.send_response(204, "", extra_headers=headers)
        conn.end_response()
        return
      }
      if request.path == "/active" {
        conn.send_response(200, "", extra_headers=headers)
        conn.write_string(active.val.to_string())
        conn.end_response()
        return
      }
      guard request.path == "/rpc" && request.meth == @http.Post else {
        conn.send_response(404, "", extra_headers=headers)
        conn.end_response()
        return
      }
      active.val += 1
      defer {
        active.val -= 1
      }
      let bytes = @async.with_timeout(2000, () => {
        let result : Array[Byte] = []
        while body.read_some(max_len=65537 - result.length()) is Some(chunk) {
          for byte in chunk {
            result.push(byte)
          }
          guard result.length() <= 65536 else {
            fail("fixture request too large")
          }
        }
        Bytes::from_array(result)
      })
      let text = @utf8.decode(bytes)
      let decoded : Request = @json.from_json(@json.parse(text))
      let mode = decoded.input.id
      if mode == "disconnect" {
        return
      }
      if mode == "timeout" {
        @async.sleep(5000)
      }
      let response = if mode == "protocol" {
        @wire.dispatch(
          endpoint, "{\"version\":1,\"procedure\":\"users.get.v1\",\"input\":{\"id\":false}}",
        )
      } else if mode == "limit" {
        @wire.dispatch(
          endpoint, "{\"version\":1,\"procedure\":\"users.get.v1\",\"input\":{\"id\":\"1\"}}",
        )
      } else {
        @wire.dispatch(endpoint, text)
      }
      if mode == "content-type" {
        headers.set(@http.CaseInsensitiveString("Content-Type"), "text/plain")
      }
      conn.send_response(response.status, "", extra_headers=headers)
      if mode == "limit" {
        let payload = response.body.stringify()
        conn.write_string(payload)
        conn.write(Bytes::make(65536 - @utf8.encode(payload).length(), b' '))
      } else if mode == "oversize" {
        conn.write(Bytes::make(65537, b' '))
      } else if mode == "invalid-json" {
        conn.write_string("{")
      } else if mode == "deep-json" {
        conn.write_string(
          Array::make(40, "[").join("") + "0" + Array::make(40, "]").join(""),
        )
      } else if mode == "slow-body" {
        let payload = response.body.stringify()
        conn.write_string(payload[:1].to_owned())
        conn.flush()
        @async.sleep(5000)
        conn.write_string(payload[1:].to_owned())
      } else {
        conn.write_string(response.body.stringify())
      }
      conn.end_response()
    },
    allow_failure=true,
    max_connections=8,
  )
}
