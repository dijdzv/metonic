///|
async fn main {
  let directory = @env.get_env_var("METONIC_WORK_ORDERS_DATA").unwrap_or_else(() => {
    @env.get_env_var("LOCALAPPDATA").unwrap() + "/MetonicWorkOrders"
  })
  let storage = @storage.create(directory)
  @window_host.run(
    @host.from_application(
      @work_orders.create(storage.snapshot(), () => storage.close()),
    ),
    controller=Some(@application_control.control),
    hidden=true,
  )
}
