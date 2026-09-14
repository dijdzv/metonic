///|
pub(all) enum DisplayObservation {
  Unavailable
  Disjoint
  Sample(UInt, UInt, Int64, UInt, UInt)
}

///|
priv struct PresentationAttempt {
  epoch : Int64
  before : UInt?
}

///|
pub(all) enum DisplayStatus {
  Confirmed
  Pending
  Unavailable
  Stale
  InvalidFrame
  NotSubmitted
  Evicted
  Closed
} derive(Eq, Debug)

///|
pub fn SurfaceRenderer::set_display_feedback(
  self : SurfaceRenderer,
  reader : (@wgpu.Surface) -> DisplayObservation,
) -> Unit {
  if self.closed || self.retention.epoch == 9223372036854775807L {
    return
  }
  self.retention.invalidate_display()
  self.retention.feedback = Some(reader)
}

///|
fn FrameRetention::invalidate_display(self : FrameRetention) -> Unit {
  if self.epoch < 9223372036854775807L {
    self.epoch += 1L
  } else {
    self.feedback = None
  }
  self.last_present = None
}

///|
fn FrameRetention::observe_display(
  self : FrameRetention,
  surface : @wgpu.Surface,
) -> UInt? {
  guard self.feedback is Some(reader) else { return None }
  match reader(surface) {
    Unavailable | Disjoint => {
      self.invalidate_display()
      None
    }
    Sample(last, observed, qpc, refresh, sync_refresh) => {
      if self.last_present is Some(previous) && last < previous {
        self.invalidate_display()
        guard self.feedback is Some(_) else { return None }
      }
      self.last_present = Some(last)
      if observed > 0U && qpc > 0L && refresh > 0U && sync_refresh > 0U {
        for pair in self.images {
          let image = pair.1
          if image.statistics_epoch == self.epoch &&
            image.present_id == Some(observed) {
            image.display_confirmed = true
          }
        }
      }
      Some(last)
    }
  }
}

///|
fn FrameRetention::begin_present(
  self : FrameRetention,
  surface : @wgpu.Surface,
) -> PresentationAttempt {
  let before = self.observe_display(surface)
  { epoch: self.epoch, before, }
}

///|
pub fn SurfaceRenderer::poll_display_confirmation(
  self : SurfaceRenderer,
  id : Int64,
) -> Bool {
  self.poll_display_status(id) == Confirmed
}

///|
pub fn SurfaceRenderer::poll_display_status(
  self : SurfaceRenderer,
  id : Int64,
) -> DisplayStatus {
  if self.closed || self.poisoned {
    return Closed
  }
  if id <= 0L {
    return InvalidFrame
  }
  if id > self.retention.sequence {
    return NotSubmitted
  }
  ignore(self.retention.observe_display(self.surface))
  for pair in self.retention.images {
    if pair.0 == id {
      let image = pair.1
      if image.display_confirmed {
        return Confirmed
      }
      if self.retention.feedback is None || image.present_id is None {
        return Unavailable
      }
      if image.statistics_epoch != self.retention.epoch {
        return Stale
      }
      return Pending
    }
  }
  Evicted
}
