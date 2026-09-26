///|
async fn main {
  @window_host.run(
    @host.from_application(@work_orders.create()),
    controller=Some(@application_control.control),
    hidden=true,
  )
}
