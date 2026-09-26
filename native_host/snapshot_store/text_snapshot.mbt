///|
pub fn Store::text_snapshot(self : Store) -> @snapshot.Snapshot {
  @snapshot.Snapshot::new(
    () => {
      try {
        match self.load() {
          None => Ok(None)
          Some(bytes) =>
            Ok(Some(@utf8.decode(bytes))) catch {
              _ => Err(@snapshot.InvalidData)
            }
        }
      } catch {
        Failure::TooLarge => Err(@snapshot.TooLarge)
        Failure::Busy => Err(@snapshot.Busy)
        Failure::Closed => Err(@snapshot.Closed)
        error if @async.is_cancellation_error(error) => raise error
        _ => Err(@snapshot.Failed)
      }
    },
    value => {
      try {
        self.save(@utf8.encode(value))
        Ok(())
      } catch {
        Failure::TooLarge => Err(@snapshot.TooLarge)
        Failure::Busy => Err(@snapshot.Busy)
        Failure::Closed => Err(@snapshot.Closed)
        error if @async.is_cancellation_error(error) => raise error
        _ => Err(@snapshot.Failed)
      }
    },
  )
}
