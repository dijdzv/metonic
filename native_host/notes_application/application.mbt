///|
pub fn create(model : @notes.Model) -> @host.Application {
  @host.from_application(model.application())
}
