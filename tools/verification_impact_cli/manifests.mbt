///|
async fn source_manifests(packages : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for package_dir in packages {
    let mut directory = @fs.realpath(package_dir).replace_all(old="\\", new="/")
    let mut package_found = false
    for name in ["moon.pkg", "moon.pkg.json"] {
      let filename = directory + "/" + name
      if @fs.exists(filename) {
        package_found = true
        if !result.contains(filename) {
          result.push(filename)
        }
      }
    }
    assert_true(package_found, msg="input package manifest missing")
    while true {
      let mut module_found = false
      for name in ["moon.mod", "moon.mod.json"] {
        let filename = directory + "/" + name
        if @fs.exists(filename) {
          module_found = true
          if !result.contains(filename) {
            result.push(filename)
          }
        }
      }
      if module_found {
        for name in ["moon.work", "moon.work.json", "moon.lock"] {
          let filename = directory + "/" + name
          if @fs.exists(filename) && !result.contains(filename) {
            result.push(filename)
          }
        }
        break
      }
      let parent = @fs.realpath(directory + "/..").replace_all(
        old="\\",
        new="/",
      )
      assert_true(parent != directory, msg="input module manifest missing")
      directory = parent
    }
  }
  result.sort()
  result
}
