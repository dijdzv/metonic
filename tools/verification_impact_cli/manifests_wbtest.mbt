///|
async test "input manifests include shared module configuration once" {
  let base = ".work/verification-manifest-tests-"
  let mut index = 0
  while @fs.exists(base + index.to_string()) {
    index += 1
  }
  let dir = base + index.to_string()
  @fs.mkdir(dir + "/a", recursive=true)
  @fs.mkdir(dir + "/b", recursive=true)
  @fs.write_file(dir + "/moon.mod", "fixture")
  @fs.write_file(dir + "/moon.work", "fixture")
  @fs.write_file(dir + "/a/moon.pkg", "fixture")
  @fs.write_file(dir + "/b/moon.pkg.json", "{}")
  let files = source_manifests([dir + "/a", dir + "/b", dir + "/a"])
  assert_eq(files.length(), 4)
  assert_true(files.any(file => file.has_suffix("/a/moon.pkg")))
  assert_true(files.any(file => file.has_suffix("/b/moon.pkg.json")))
  assert_true(files.any(file => file.has_suffix("/moon.work")))
  @fs.remove(dir + "/a/moon.pkg")
  let rejected = try {
    ignore(source_manifests([dir + "/a"]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
