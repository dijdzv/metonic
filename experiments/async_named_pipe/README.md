# Windows named-pipe listener experiment

This patch evaluates a cancellable local duplex endpoint using the existing
`moonbitlang/async` IOCP event loop. Native dependency preparation applies it into
`sources/async-local-control`. The development host can select a listener using
`METONIC_DEV_PIPE`; discovery and lifecycle acceptance remain unfinished. Integration is tracked in
[issue 197](https://github.com/dijdzv/metonic/issues/197).

The baseline is async 0.21.2, using the archive prepared by
`scripts/prepare-native-deps.mbtx`:
SHA-256 `742ee3d84d33d4602953741fb49f310ae5c8814648079facaa4b595d986c1618`.
Run the combined waiter/listener verification from the repository root after
normal native dependency preparation:

```text
mise exec -- ./.tools/moonbit/bin/moon.exe run scripts/verify-named-pipe.mbtx
```

The script verifies the archive checksum, extracts fresh sources, applies both
patches and requires five internal tests plus one public API test. It retains the log at
`.work/named-pipe-verification.log` and removes its owned extraction on success.
A failed extraction is retained for diagnosis and must be inspected before removal
and retry. The verifier itself does not alter the application's prepared dependencies.

For manual inspection, apply `windows-named-pipe.patch` to an independent extraction of that archive.
When applying from the Metonic repository, use `git apply --directory=<extraction>`;
running `git -C <extraction> apply` inside this repository can silently skip paths.
Require the added `src/internal/event_loop/pipe_accept_wbtest.mbt` to exist, then run:

```text
mise exec -- ./.tools/moonbit/bin/moon.exe -C <extraction> test src/internal/event_loop --target native --filter '*pipe*'
```

Require five internal tests, not merely exit code zero. The script additionally
runs `src/named_pipe --filter '*public Windows pipe*'` and requires one passing test.
That public test leaves unread text in one connection and confirms the next
connection receives only its own text. Tests cover accept cancellation,
early/delayed connection and duplex traffic, read cancellation and reconnection,
cancel-before-close with endpoint recreation and aggregate handle counts, and
restricted-token denial with a default-security positive control. They do not
prove arbitrary close during pending I/O, every cancellation race, another-account
login or access from another machine.

The proposed library extension uses MoonBit for waiting, cancellation and lifetime
coordination. C creates the user-DACL/remote-rejecting Windows pipe and crosses the
overlapped I/O ABI. Test-only C also queries process handles and temporarily uses
a restricted token. Those helpers live in `internal/pipe_test_support`, imported
only by the event loop's white-box tests.
No test coroutine runs while impersonating. The API permits one accept/read at a
time, with one pipe instance; callers must cancel and await outstanding operations
before disconnecting or closing. `disconnect_pipe` checks errors instead of using
the existing test-only void disconnect helper.

This is an upstream-compatible extension candidate, not an upstream submission.
The public `named_pipe.WindowsPipe` API provides a validated local name, accept,
Reader/Writer operations, checked disconnect and close. Disconnect resets the
buffer so bytes cannot leak into the next connection. Application integration is
exercised by `mise run native:window-attach`; production exclusion checks generated
code, link inputs and executable symbols in
`scripts/verify-window-production-exclusion.mbtx`. Current review status and
outstanding tasks belong to the issue.
