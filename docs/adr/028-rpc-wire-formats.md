# ADR 028: Default RPC wire format and optional gRPC

Date: 2026-09-06.

Status: selected for the initial implementation; protocol compatibility is not yet stable.

## Context

The primary application shares MoonBit API contracts between its frontend and
backend. Those contracts must remain usable without a UI runtime, code generator,
Protobuf dependency or gRPC transport. Calling existing gRPC services is a separate,
optional requirement. A generator's existence does not make it a required part of
the standard RPC implementation.

HTTP is a transport/application protocol; JSON and Protobuf are data encodings.
Protobuf can be carried over ordinary HTTP without gRPC. Choosing a typed API also
does not choose its wire encoding: compile-time types and runtime validation are
both necessary with either encoding.

## Decision

Start standard unary RPC with HTTP and JSON. MoonBit contracts in application
`backend/api` packages remain the source of application types. Keep the pure
contract, JSON codec/envelope, and HTTP host in separate packages. This is a
tRPC-style development model, not a claim of tRPC wire compatibility.

For an optional gRPC endpoint, use `.proto` as its wire-schema source and generate
DTOs with a pinned generator/runtime. Use Protobuf there instead of inventing a
different gRPC codec. Map those DTOs at the optional adapter boundary; do not
maintain the same field-number schema independently in handwritten MoonBit code.
Standard RPC builds and tests must not require that adapter or its generator.

The browser gRPC path is not selected by this decision. Connect or gRPC-Web still
requires method, framing, metadata, status, deadline and cancellation verification
against a compatible server or proxy. Protobuf encode/decode success alone cannot
establish any of those properties.

## Alternatives and tradeoffs

| Choice | Benefit | Cost for the current application |
| --- | --- | --- |
| HTTP + JSON | Direct browser interoperability and inspectable messages; fits shared MoonBit API types | Explicit validation, evolution and non-JSON scalar mappings are required |
| HTTP + Protobuf as the default | Schema-first generation and language-independent field identity | Makes schema/code generation part of the standard workflow before that requirement is established |
| gRPC + Protobuf as the default | Existing gRPC service interoperability | Adds mandatory transport and browser compatibility work despite gRPC being optional |

JSON is selected because of the contract ownership and initial deployment model,
not because it is always faster or because Protobuf cannot work with browsers.
No representative payload-size, CPU or latency benchmark has established an
encoding-performance requirement for metonic. A later measurement can change the
choice without changing the application-facing procedure abstraction.

## Wire contracts still required

The HTTP/JSON implementation must specify protocol version, procedure identity,
content type, request/response limits, timeouts and cancellation. Domain failures
must remain distinct from transport failure and malformed or unsupported responses.
Unknown procedures, missing fields and wrong field types must not reach a handler.

JSON does not remove representation choices. Decimal strings preserve signed and
unsigned 64-bit integers without passing through JavaScript Number; this also
matches the pinned MoonBit core's Int64/UInt64 JSON implementations. Bytes, dates,
non-finite numbers, enum changes and absent/null semantics need explicit codec
contracts before application APIs expose them. A generic derive is not proof of
cross-language compatibility for every MoonBit type. The initial sample contains
string input/output fields, with separate scalar-profile tests where implemented.

## Implementation tracking

Track standard RPC implementation and intermediate validation in
[issue #29](https://github.com/dijdzv/metonic/issues/29), and optional generator
compatibility and gRPC interoperability in
[issue #4](https://github.com/dijdzv/metonic/issues/4).
Compiler or dependency compatibility failures do not determine the default wire
format. Server runtime support also does not establish browser client support or
UI event-loop integration; validate those boundaries independently.

## Reconsideration

Reconsider the default encoding if generated clients for other languages become
a primary requirement, a shared external `.proto` schema becomes authoritative,
or representative profiling shows meaningful JSON overhead. Evaluate conversion
costs, generator compatibility and browser/native results before switching.
Adding an optional gRPC integration alone does not trigger a default-format change.

## References

- [Protocol Buffers overview](https://protobuf.dev/overview/)
- [gRPC core concepts](https://grpc.io/docs/what-is-grpc/core-concepts/)
- [tRPC HTTP RPC specification](https://trpc.io/docs/rpc)
- [Connect introduction](https://connectrpc.com/docs/introduction/)
- [MoonBit generator source](https://github.com/moonbitlang/protoc-gen-mbt/tree/9ac87899cf20ea88e31ba77330958ba389eab5fd)
