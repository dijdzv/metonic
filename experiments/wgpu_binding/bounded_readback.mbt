///|
/// A caller-owned ticket registry keeps pending native requests alive explicitly.
pub(all) struct ReadbackTicket {
  pub id : Int
  pub poll : () -> UInt
  pub read : () -> Bytes
  pub cancel : () -> Unit
  pub clear : () -> Unit
}

///|
pub(all) suberror ReadbackTimeout derive(Debug)

///|
pub(all) suberror ReadbackFailed {
  ReadbackFailed(UInt)
} derive(Debug)

///|

///|
async fn poll_until(
  ticket : ReadbackTicket,
  timeout_ms : Int,
  poll_limit : Int,
) -> UInt? {
  if poll_limit <= 0 {
    return None
  }
  let nested = @async.with_timeout_opt(timeout_ms, () => {
    let mut count = 0
    let mut status = (ticket.poll)()
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
async fn cleanup_ticket(
  ticket : ReadbackTicket,
  registry : Map[Int, ReadbackTicket],
  cleanup_ms : Int,
  cleanup_poll_limit : Int,
) -> Bool {
  (ticket.cancel)()
  match poll_until(ticket, cleanup_ms, cleanup_poll_limit) {
    Some(_) => {
      (ticket.clear)()
      registry.remove(ticket.id)
      true
    }
    None => false
  }
}

///|
/// Run one asynchronous readback. Status zero is pending and nonzero is
/// terminal; status one denotes success. Pending tickets remain in registry.
pub async fn run_readback(
  ticket : ReadbackTicket,
  registry : Map[Int, ReadbackTicket],
  timeout_ms? : Int = 10000,
  cleanup_ms? : Int = 1000,
  poll_limit? : Int = 100000,
  cleanup_poll_limit? : Int = 1000,
) -> Bytes raise Error {
  if registry.get(ticket.id) is Some(_) {
    raise ReadbackFailed(0U)
  }
  registry.set(ticket.id, ticket)
  let outcome : Result[Bytes, Error] = try {
    match poll_until(ticket, timeout_ms, poll_limit) {
      None => Err(ReadbackTimeout)
      Some(status) =>
        if status == 1U {
          let bytes = (ticket.read)()
          (ticket.clear)()
          registry.remove(ticket.id)
          Ok(bytes)
        } else {
          (ticket.clear)()
          registry.remove(ticket.id)
          Err(ReadbackFailed(status))
        }
    }
  } catch {
    error => {
      @async.protect_from_cancel <| () => {
        ignore(cleanup_ticket(ticket, registry, cleanup_ms, cleanup_poll_limit))
      }
      Err(error)
    }
  }
  match outcome {
    Ok(bytes) => {
      @async.pause()
      bytes
    }
    Err(error) => {
      if error is ReadbackTimeout {
        @async.protect_from_cancel <| () => {
          ignore(
            cleanup_ticket(ticket, registry, cleanup_ms, cleanup_poll_limit),
          )
        }
      }
      raise error
    }
  }
}
