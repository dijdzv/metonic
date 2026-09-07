///|
async fn fail_response(
  conn : @http.ServerConnection,
  code : Int,
  message : String,
) -> Unit {
  let headers : Map[@http.CaseInsensitiveString, String] = Map([])
  headers.set(@http.CaseInsensitiveString("Connection"), "close")
  headers.set(@http.CaseInsensitiveString("Cache-Control"), "no-store")
  conn.send_response(code, message, extra_headers=headers)
  conn.end_response()
}

///|
async fn main {
  let endpoint = @wire.endpoint(@handlers.binding(), error => {
    match error {
      NotFound => "not_found"
    }
  })
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:4173"))
  defer server.close()
  println("http://127.0.0.1:4173/")
  server.run_forever(
    async fn(req, body, conn) {
      defer conn.close()
      if req.path == "/rpc" {
        @transport.serve(endpoint, req, body, conn)
        return
      }
      let request_method = req.meth
      if request_method != @http.Get && request_method != @http.Head {
        let headers : Map[@http.CaseInsensitiveString, String] = Map([])
        headers.set(@http.CaseInsensitiveString("Connection"), "close")
        headers.set(@http.CaseInsensitiveString("Cache-Control"), "no-store")
        headers.set(@http.CaseInsensitiveString("Allow"), "GET, HEAD")
        conn.send_response(405, "Method Not Allowed", extra_headers=headers)
        conn.end_response()
      } else {
        let raw_path = req.path
        let path = match raw_path.find("?") {
          Some(i) => raw_path[:i].to_owned()
          None => raw_path
        }
        let entry = match path {
          "/" => Some(("index.html", "text/html; charset=utf-8"))
          "/index.html" => Some(("index.html", "text/html; charset=utf-8"))
          "/style.css" => Some(("style.css", "text/css; charset=utf-8"))
          "/host.mjs" => Some(("host.mjs", "text/javascript; charset=utf-8"))
          "/loader.mjs" =>
            Some(("loader.mjs", "text/javascript; charset=utf-8"))
          "/text-renderer.mjs" =>
            Some(("text-renderer.mjs", "text/javascript; charset=utf-8"))
          "/app.mjs" => Some(("app.mjs", "text/javascript; charset=utf-8"))
          "/app.wasm" => Some(("app.wasm", "application/wasm"))
          "/NotoSansJP.ttf" => Some(("NotoSansJP.ttf", "font/ttf"))
          "/OFL.txt" => Some(("OFL.txt", "text/plain; charset=utf-8"))
          _ => None
        }
        match entry {
          None => fail_response(conn, 404, "Not Found")
          Some((filename, content_type)) => {
            let content = Some(
              @fs.read_file(".work/browser-dist/" + filename).binary(),
            ) catch {
              _ => None
            }
            match content {
              None => fail_response(conn, 404, "Not Found")
              Some(bytes) => {
                let headers : Map[@http.CaseInsensitiveString, String] = Map([])
                headers.set(@http.CaseInsensitiveString("Connection"), "close")
                headers.set(
                  @http.CaseInsensitiveString("Cache-Control"),
                  "no-store",
                )
                headers.set(
                  @http.CaseInsensitiveString("Content-Type"),
                  content_type,
                )
                headers.set(
                  @http.CaseInsensitiveString("Content-Length"),
                  bytes.length().to_string(),
                )
                conn.send_response(200, "OK", extra_headers=headers)
                if request_method == @http.Get {
                  conn.write(bytes)
                }
                conn.end_response()
              }
            }
          }
        }
      }
    },
    allow_failure=true,
    max_connections=8,
  )
}
