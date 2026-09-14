///|
#borrow(output)
extern "C" fn feedback(
  surface : @c.WGPUSurface,
  output : FixedArray[Int64],
) -> Int = "metonicSurfaceReadDisplayFeedback"

///|
async fn main {
  let words : FixedArray[Int64] = [0L, 0L, 0L]
  @control.run(
    display_feedback=Some((surface : @wgpu.Surface) => {
      let status = feedback(surface.raw, words)
      if status == -2005270517 {
        @gpu.DisplayObservation::Disjoint
      } else if status != 0 {
        @gpu.DisplayObservation::Unavailable
      } else {
        let ids = words[0].reinterpret_as_uint64()
        let refresh = words[2].reinterpret_as_uint64()
        @gpu.DisplayObservation::Sample(
          ids.to_uint(),
          (ids >> 32).to_uint(),
          words[1],
          refresh.to_uint(),
          (refresh >> 32).to_uint(),
        )
      }
    }),
  )
}
