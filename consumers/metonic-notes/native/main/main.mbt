///|
async fn main {
  let directory = @env.get_env_var("METONIC_NOTES_DATA").unwrap_or_else(() => {
    @env.get_env_var("LOCALAPPDATA").unwrap() + "/MetonicNotes"
  })
  let storage = @storage.create(directory)
  @window_host.run(
    minimum_size=Some((320, 360)),
    @host.from_application(
      @model.create_collection(storage.adapter(), () => storage.dispose()),
    ),
  )
}
