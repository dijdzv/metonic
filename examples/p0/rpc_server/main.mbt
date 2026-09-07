///|
async fn main {
  let binding = @handlers.binding()
  let endpoint = @wire.endpoint(binding, fn(error) {
    match error {
      NotFound => "not_found"
    }
  })
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  println("RPC_READY " + server.addr.to_string())
  server.run_forever(
    async fn(request, body, connection) {
      defer connection.close()
      @transport.serve(endpoint, request, body, connection)
    },
    allow_failure=true,
    max_connections=8,
  )
}
