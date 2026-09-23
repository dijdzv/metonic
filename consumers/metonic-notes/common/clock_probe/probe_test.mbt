///|
async test "external operations share production time without sharing cancellation" {
  @clock_probe.verify()
}
