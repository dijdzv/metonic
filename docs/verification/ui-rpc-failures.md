# Integrated UI HTTP failures

Run `mise run native:window-rpc` and `mise run browser:headless` with the pinned
setup. The paired hooks run these runtime checks in the pre-push gate; native
RPC checks are included through `native:window-integration`. The complete manual
gate also includes them. See [local verification](../development.md#local-pre-commit-checks)
for the commit/push split and successful-input record rules.
`browser:headless` can run without desktop interaction; `native:window-rpc`
requires the native window path and must be deferred during headless-only work.
Browser uses the packaged WasmGC page; native uses
`window_dev`, sharing the ordinary UI loop/client. This does not establish native
production OS-input observation.

Each failure is followed by editing and a successful lookup, preserving text.

| Real HTTP condition | Displayed error |
| --- | --- |
| No headers for five seconds | `timeout` |
| Body stalls for five seconds | `timeout` |
| Server closes without a response | `transport_error` |
| Body exceeds 65,536 bytes | `response_too_large` |
| Malformed JSON or nesting beyond 32 | `invalid_json` |
| Incorrect content type | `invalid_content_type` |
| Dispatcher rejects an invalid typed payload | `protocol:invalid_input` |

A response padded to exactly 65,536 bytes succeeds. `rpc:verify` also sends invalid
requests to the ordinary server and checks rejection/recovery. The fixture's
protocol case substitutes an invalid typed payload before the same dispatcher;
it does not claim a well-typed UI generated invalid JSON.

Cancellation/replacement waits for a request in progress. A new success must stay
current after the old handler finishes. Sequences wait for zero active fixture
handlers. Native closes stdin with HTTP pending and must exit successfully within
two seconds, before its normal timeout. Browser Stop with HTTP pending must
disable input and preserve the stopped frame after delayed work and late input.

`tools/rpc_fault_server` binds an ephemeral loopback port and is owned by the
MoonBit native verifier or browser supervisor. Handlers last at most five seconds,
with eight concurrent connections. Active-handler accounting and child exit are
bounded cleanup evidence, not a system-wide socket/heap leak measurement.

Playwright rewrites the RPC destination using `route.continue`, without fulfilling
or buffering responses. Fetch, stream reading and abort handling execute in the
packaged application. The fixture permits this test origin; arbitrary production
CORS policies and Internet behavior are outside this check.

Server and clients use `rpc/json/parse_bounded` and the existing parser. The pinned
parser deprecates its depth-limit label without exposing a replacement parameter.
The warning stays in this helper, preserving the bound without a custom parser.
Native previously used the larger default; browser/server already limited depth.

The application server and browser ZIP contain no fault routes or fixture.
Physical IME, accessibility and native production interaction remain separate.
