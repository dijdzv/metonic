///|
priv struct Waiter {
  id : Int64
  deadline : Int64
  signal : @cond_var.Cond
  mut ready : Bool
}

///|
pub struct VirtualClock {
  priv mut time : Int64
  priv mut next_id : Int64
  priv waiters : Array[Waiter]
}

///|
pub fn VirtualClock::new(
  start? : Int64 = 0L,
) -> VirtualClock raise @capability.InvalidTime {
  if start < 0L {
    raise @capability.InvalidTime
  }
  { time: start, next_id: 0L, waiters: [], }
}

///|
fn deadline(
  time : Int64,
  milliseconds : Int,
) -> Int64 raise @capability.InvalidTime {
  if milliseconds < 0 || time > 9223372036854775807L - milliseconds.to_int64() {
    raise @capability.InvalidTime
  }
  time + milliseconds.to_int64()
}

///|
pub impl @capability.Clock for VirtualClock with fn now(self) {
  self.time
}

///|
pub impl @capability.Clock for VirtualClock with fn sleep(self, milliseconds) {
  let due = deadline(self.time, milliseconds)
  if milliseconds == 0 {
    return
  }
  if self.next_id == 9223372036854775807L {
    raise @capability.InvalidTime
  }
  let waiter = Waiter::{
    id: self.next_id,
    deadline: due,
    signal: @cond_var.Cond(),
    ready: false,
  }
  self.next_id += 1L
  self.waiters.push(waiter)
  defer self.waiters.retain(entry => entry.id != waiter.id)
  while !waiter.ready {
    waiter.signal.wait()
  }
}

///|
pub fn VirtualClock::advance(
  self : VirtualClock,
  milliseconds : Int,
) -> Unit raise @capability.InvalidTime {
  self.time = deadline(self.time, milliseconds)
  self.waiters.sort_by((a, b) => {
    let order = a.deadline.compare(b.deadline)
    if order == 0 {
      a.id.compare(b.id)
    } else {
      order
    }
  })
  for waiter in self.waiters {
    if waiter.deadline <= self.time && !waiter.ready {
      waiter.ready = true
      waiter.signal.signal()
    }
  }
}

///|
pub fn VirtualClock::pending(self : VirtualClock) -> Int {
  self.waiters.length()
}
