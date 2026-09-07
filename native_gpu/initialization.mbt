///|
pub struct InitTicket {
  id : Int
  poll : () -> UInt
  take : () -> Unit raise Error
  discard : () -> Unit
  clear : () -> Unit
}

///|
pub struct InitEntry {
  ticket : InitTicket
  mut abandoned : Bool
}

///|
pub struct Initialization {
  entries : Map[Int, InitEntry]
  mut next_id : Int
}

///|
pub fn Initialization::new() -> Initialization {
  { entries: Map([]), next_id: 0, }
}

///|
pub fn Initialization::pending_count(self : Initialization) -> Int {
  self.entries.length()
}

///|
pub fn Initialization::reap(self : Initialization) -> Int {
  let ids = self.entries.keys()
  for id in ids {
    match self.entries.get(id) {
      Some(entry) if entry.abandoned => {
        let status = (entry.ticket.poll)()
        if status != 0U {
          (entry.ticket.discard)()
          (entry.ticket.clear)()
          self.entries.remove(id)
        }
      }
      _ => ()
    }
  }
  self.entries.length()
}

///|
pub suberror InitializationTimeout derive(Debug)

///|
pub suberror InitializationFailed {
  InitializationFailed(UInt)
} derive(Debug)

///|
async fn poll_until_terminal(
  ticket : InitTicket,
  timeout_ms : Int,
  poll_limit : Int,
) -> UInt? {
  if poll_limit <= 0 {
    return None
  }
  let nested = @async.with_timeout_opt(timeout_ms, () => {
    let mut status = (ticket.poll)()
    let mut count = 0
    while status == 0U && count < poll_limit {
      @async.sleep(1)
      status = (ticket.poll)()
      count += 1
    }
    if status == 0U {
      None
    } else {
      Some(status)
    }
  })
  match nested {
    Some(value) => value
    None => None
  }
}

///|
async fn cleanup_abandoned(
  ticket : InitTicket,
  owner : Initialization,
  cleanup_ms : Int,
  cleanup_poll_limit : Int,
) -> Bool {
  let terminal = poll_until_terminal(ticket, cleanup_ms, cleanup_poll_limit)
  match terminal {
    Some(_) => {
      (ticket.discard)()
      (ticket.clear)()
      owner.entries.remove(ticket.id)
      true
    }
    None => false
  }
}

///|
async fn run_initialization(
  ticket : InitTicket,
  owner : Initialization,
  timeout_ms? : Int = 10000,
  cleanup_ms? : Int = 1000,
  poll_limit? : Int = 100000,
  cleanup_poll_limit? : Int = 1000,
) -> Unit raise Error {
  if owner.entries.get(ticket.id) is Some(_) {
    raise InitializationFailed::InitializationFailed(0U)
  }
  owner.entries.set(ticket.id, { ticket, abandoned: false, })
  let outcome : Result[Unit, Error] = try {
    match poll_until_terminal(ticket, timeout_ms, poll_limit) {
      None => raise InitializationTimeout::InitializationTimeout
      Some(status) if status == 1U => {
        @async.pause()
        (ticket.take)()
        (ticket.clear)()
        owner.entries.remove(ticket.id)
        Ok(())
      }
      Some(status) => {
        (ticket.discard)()
        (ticket.clear)()
        owner.entries.remove(ticket.id)
        Err(InitializationFailed::InitializationFailed(status))
      }
    }
  } catch {
    error => {
      let drained : Ref[Bool] = @ref.new(false)
      @async.protect_from_cancel <| () => {
        drained.val = cleanup_abandoned(
          ticket, owner, cleanup_ms, cleanup_poll_limit,
        )
      }
      if !drained.val {
        match owner.entries.get(ticket.id) {
          Some(_) => owner.entries[ticket.id].abandoned = true
          None => ()
        }
      }
      Err(error)
    }
  }
  match outcome {
    Ok(_) => ()
    Err(error) => raise error
  }
}
