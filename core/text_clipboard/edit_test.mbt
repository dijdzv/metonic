///|
test "failed cut keeps Unicode selection and successful cut writes before deletion" {
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "A😀日本B").unwrap()
  assert_eq(@semantics.focus(tree, input), "")
  assert_eq(@semantics.set_selection_directed(tree, input, 5, 1), "")
  let before = @semantics.revision(tree)
  let writes = Ref(0)
  let backend : Backend = {
    read: () => abort("cut must not read"),
    write: text => {
      assert_eq(text, "😀日本") catch {
        _ => abort("wrong clipboard selection")
      }
      writes.val += 1
      Err("clipboard busy")
    },
  }
  assert_eq(apply(tree, input, Cut, backend), Err("clipboard busy"))
  assert_eq(@semantics.revision(tree), before)
  assert_eq(@semantics.node(tree, input).unwrap().selection_anchor, 5)
  let accepted : Backend = {
    ..backend,
    write: text => {
      if text != "😀日本" ||
        @semantics.node(tree, input).unwrap().value != "A😀日本B" {
        abort("text was removed before clipboard write")
      }
      writes.val += 1
      Ok(())
    },
  }
  assert_eq(apply(tree, input, Cut, accepted), Ok(Edited))
  assert_eq(writes.val, 2)
  let edited = @semantics.node(tree, input).unwrap()
  assert_eq(edited.value, "AB")
  assert_eq((edited.selection_start, edited.selection_end), (1, 1))
}

///|
test "paste replaces selection and normalizes multiline and single-line input" {
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "before").unwrap()
  assert_eq(@semantics.focus(tree, input), "")
  assert_eq(@semantics.set_selection(tree, input, 0, 6), "")
  let backend : Backend = {
    read: () => Ok(Some("日本\r\n😀\r末尾")),
    write: _ => abort("paste must not write"),
  }
  assert_eq(apply(tree, input, Paste, backend), Ok(Edited))
  assert_eq(@semantics.node(tree, input).unwrap().value, "日本\n😀\n末尾")
  assert_eq(@semantics.set_selection(tree, input, 0, 8), "")
  assert_eq(apply(tree, input, Paste, backend, single_line=true), Ok(Edited))
  assert_eq(@semantics.node(tree, input).unwrap().value, "日本😀末尾")
}

///|
test "empty clipboard and read failure preserve a selected value" {
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "keep").unwrap()
  assert_eq(@semantics.focus(tree, input), "")
  assert_eq(@semantics.set_selection(tree, input, 0, 4), "")
  let before = @semantics.revision(tree)
  for result in [Ok(None), Ok(Some("")), Err("read denied")] {
    let backend : Backend = {
      read: () => result,
      write: _ => abort("unexpected write"),
    }
    let actual = apply(tree, input, Paste, backend)
    assert_eq(
      actual,
      if result is Err(error) {
        Err(error)
      } else {
        Ok(Unchanged)
      },
    )
    assert_eq(@semantics.revision(tree), before)
  }
}

///|
test "preedit and empty selection do not access the clipboard" {
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "日本語").unwrap()
  assert_eq(@semantics.focus(tree, input), "")
  let backend : Backend = {
    read: () => abort("unexpected read"),
    write: _ => abort("unexpected write"),
  }
  assert_eq(apply(tree, input, Copy, backend), Ok(Unchanged))
  assert_eq(apply(tree, input, Cut, backend), Ok(Unchanged))
  assert_eq(@semantics.set_selection(tree, input, 0, 3), "")
  for action in [Action::Copy, Cut, Paste] {
    assert_eq(
      apply(tree, input, action, backend, composing=true),
      Ok(Unchanged),
    )
  }
  assert_eq(@semantics.set_enabled(tree, input, false), "")
  assert_eq(apply(tree, input, Paste, backend), Err("disabled"))
}

///|
test "a backend cannot make cut delete a newer selection" {
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "abc").unwrap()
  assert_eq(@semantics.focus(tree, input), "")
  assert_eq(@semantics.set_selection(tree, input, 0, 2), "")
  let backend : Backend = {
    read: () => Ok(None),
    write: _ => {
      ignore(@semantics.set_selection(tree, input, 2, 3))
      Ok(())
    },
  }
  assert_eq(apply(tree, input, Cut, backend), Err("stale_selection"))
  assert_eq(@semantics.node(tree, input).unwrap().value, "abc")
  assert_eq(@semantics.node(tree, input).unwrap().selection_start, 2)
}

///|
test "paste cannot replace text changed by the backend" {
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "original").unwrap()
  assert_eq(@semantics.focus(tree, input), "")
  assert_eq(@semantics.set_selection(tree, input, 0, 8), "")
  let backend : Backend = {
    read: () => {
      ignore(@semantics.replace_selection(tree, input, "newer"))
      Ok(Some("clipboard"))
    },
    write: _ => abort("unexpected write"),
  }
  assert_eq(apply(tree, input, Paste, backend), Err("stale_selection"))
  assert_eq(@semantics.node(tree, input).unwrap().value, "newer")
}

///|
test "NUL clipboard text cannot truncate or delete selected text" {
  let tree = @semantics.empty(1, 1)
  let input = @semantics.add_input(tree, "Memo", "keep").unwrap()
  assert_eq(@semantics.focus(tree, input), "")
  assert_eq(@semantics.set_selection(tree, input, 0, 4), "")
  let before = @semantics.revision(tree)
  let backend : Backend = {
    read: () => Ok(Some("prefix\u0000suffix")),
    write: _ => abort("unexpected write"),
  }
  assert_eq(apply(tree, input, Paste, backend), Err("invalid_clipboard_text"))
  assert_eq(@semantics.revision(tree), before)
}
