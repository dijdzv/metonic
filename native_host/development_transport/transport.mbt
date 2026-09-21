///|
pub struct ConnectionState {
  mut ended : Bool
  changed : @cond_var.Cond
}

///|
priv suberror SessionQueueOverflow

///|
pub async fn ConnectionState::wait_end(self : ConnectionState) -> String {
  defer self.changed.broadcast()
  while !self.ended {
    self.changed.wait()
  }
  "disconnected"
}

///|
pub type Handler = async (Bytes, Ref[Int], &@io.Writer, String?, ConnectionState, String) -> Unit

///|
async fn session(
  respond : Handler,
  input : &@io.Reader,
  output : &@io.Writer,
  identity : String?,
  frame_scope : String,
) -> Unit {
  let pending : @aqueue.Queue[@lines.InputLine] = @aqueue.Queue(
    kind=@aqueue.Blocking(64),
  )
  let connection = ConnectionState::{ ended: false, changed: @cond_var.Cond(), }
  defer pending.close(clear=true)
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      let lines = @lines.Lines::new(lf_only=true)
      defer {
        connection.ended = true
        connection.changed.broadcast()
        pending.close()
      }
      while input.read_some(max_len=1024) is Some(chunk) {
        for line in lines.feed(chunk) {
          // WhyNot: blocking admission would hide EOF behind a full request queue.
          if !pending.try_put(line) {
            raise SessionQueueOverflow
          }
        }
      }
      for line in lines.finish() {
        if !pending.try_put(line) {
          raise SessionQueueOverflow
        }
      }
    }
    let last_id = Ref(0)
    while true {
      let line = pending.get() catch {
        @aqueue.QueueAlreadyClosed => break
        error => raise error
      }
      match line {
        @lines.InputLine::Line(bytes) =>
          respond(
            bytes, last_id, output, identity, connection, frame_scope,
          )
        @lines.InputLine::TooLong =>
          output.write("{\"id\":null,\"error\":\"line_too_long\"}\n")
      }
    }
  }
}

///|
pub async fn run(respond : Handler, close : async () -> Unit) -> Unit {
  let reservation = @fs.tmpdir(prefix="metonic-session")
  defer @async.protect_from_cancel(() => @fs.rmdir(reservation))
  let parts = reservation.replace_all(old="\\", new="/").split("/").to_array()
  let identity = parts[parts.length() - 1].to_owned()
  match @env.get_env_var("METONIC_DEV_PIPE") {
    None => {
      session(respond, @stdio.stdin, @stdio.stdout, None, identity) catch {
        SessionQueueOverflow =>
          @stdio.stderr.write("control request queue exceeded\n")
        error => raise error
      }
      close()
    }
    Some(name) => {
      let pipe = @pipe.WindowsPipe::listen(name)
      defer pipe.close()
      let discovery_path = reservation + "/session.json"
      let discovery : Json = {
        "protocol_version": 1,
        "session_id": identity,
        "pipe": pipe.path(),
      }
      defer @async.protect_from_cancel(() => {
        if @fs.exists(discovery_path) {
          @fs.remove(discovery_path)
        }
      })
      @fs.write_file(discovery_path, discovery.stringify())
      @stdio.stderr.write("METONIC_DEV_SESSION " + discovery_path + "\n")
      @stdio.stderr.write("METONIC_DEV_PIPE_READY " + pipe.path() + "\n")
      while true {
        pipe.accept()
        session(respond, pipe, pipe, Some(identity), identity) catch {
          error if @async.is_cancellation_error(error) => raise error
          error =>
            @stdio.stderr.write(
              "control connection ended: " + error.to_string() + "\n",
            )
        }
        pipe.disconnect()
      }
    }
  }
}
