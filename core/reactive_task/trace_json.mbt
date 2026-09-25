///|
fn trace_kind_name(kind : TraceKind) -> String {
  match kind {
    RequestAdmitted => "request_admitted"
    PendingTransition => "pending"
    ReadyTransition => "ready"
    FailedTransition => "failed"
    ExpectedFailure => "expected_failure"
    UnexpectedFailure => "unexpected_failure"
    CanceledTransition => "canceled"
    CancellationRequested => "cancel_requested"
    AdmissionRejected => "admission_rejected"
    ProgressRejected => "progress_rejected"
    CompletionRejected => "completion_rejected"
    FailureRejected => "failure_rejected"
    OwnerDisposed => "owner_disposed"
    SourceDisposed => "source_disposed"
    CleanupJoined => "cleanup_joined"
  }
}

///|
fn denial_name(reason : @task.AdmissionDenial) -> String {
  match reason {
    @task.DriverClosed => "driver_closed"
    @task.EmptyGroup => "empty_group"
    @task.PendingCapacity => "pending_capacity"
    @task.NestedGroup => "nested_group"
    @task.DuplicateOperation => "duplicate_operation"
    @task.LaneCapacity => "lane_capacity"
    @task.QueueFull => "queue_full"
  }
}

///|
fn origin_json(origin : TraceOrigin) -> Json {
  {
    "source_id": origin.source_id,
    "admission_id": origin.admission_id,
    "revision": origin.revision,
    "cycle_id": origin.cycle_id,
  }
}

///|
fn cause_json(cause : TraceCause) -> Json {
  match cause {
    IdleCause(id) => { "kind": "idle", "source_id": id }
    OtherRequestCause(id) => { "kind": "other_request", "source_id": id }
    PendingCause(origin) => { "kind": "pending", "origin": origin_json(origin) }
    FailedCause(origin) => { "kind": "failed", "origin": origin_json(origin) }
    CanceledCause(origin) =>
      { "kind": "canceled", "origin": origin_json(origin) }
    ConflictCause(id, first, second) =>
      {
        "kind": "origin_conflict",
        "source_id": id,
        "first": origin_json(first),
        "second": origin_json(second),
      }
    RelatedMismatchCause => { "kind": "related_mismatch" }
    DownstreamCause(id, reason) =>
      {
        "kind": "downstream_blocked",
        "source_id": id,
        "reason": match reason {
          WaitingUpstream => "waiting_upstream"
          NotAdmitted => "not_admitted"
          AdmissionRejected => "admission_rejected"
        },
      }
  }
}

///|
pub fn TraceRegistry::snapshot_json(self : TraceRegistry) -> Json {
  {
    "version": 1,
    "capacity": self.capacity,
    "dropped": self.dropped,
    "owners": Json::array(
      self
      .owners()
      .map(owner => {
        "id": owner.id,
        "parent_id": owner.parent_id.to_json(),
        "kind": match owner.kind {
          ApplicationOwner => "application"
          ComponentOwner => "component"
        },
        "generation": owner.generation,
      }),
    ),
    "sources": Json::array(
      self
      .sources()
      .map(source => {
        "id": source.source_id,
        "operation_id": source.operation_id,
        "owner_id": source.owner_id,
        "key_id": source.key_id.to_json(),
        "cycle_id": source.cycle_id.to_json(),
        "admission_id": source.admission_id,
        "revision": source.revision,
        "phase": source.phase,
        "cleanup_pending": Json::array(
          source.cleanup_pending.map(item => item.to_json()),
        ),
      }),
    ),
    "derived": Json::array(
      self
      .derived()
      .map(item => {
        "id": item.id,
        "owner_id": item.owner_id,
        "phase": item.phase,
        "causes": Json::array(item.causes.map(cause_json)),
        "origins": Json::array(item.origins.map(origin_json)),
      }),
    ),
    "events": Json::array(
      self
      .events()
      .map(event => {
        "sequence": event.sequence,
        "kind": trace_kind_name(event.kind),
        "source_id": event.source_id,
        "operation_id": event.operation_id,
        "owner_id": event.owner_id,
        "key_id": event.key_id.to_json(),
        "cycle_id": event.cycle_id.to_json(),
        "admission_id": event.admission_id,
        "revision": event.revision,
        "driver_generation": event.driver_generation.to_json(),
        "cleanup_pending": Json::array(
          event.cleanup_pending.map(item => item.to_json()),
        ),
        "denial": event.denial.map(denial_name).to_json(),
      }),
    ),
  }
}
