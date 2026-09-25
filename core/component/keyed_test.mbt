///|
priv struct TestChild {
  owner : ChildOwner
  reference : @semantics.NodeRef
  name : @reactive.Signal[String]
}

///|
test "keyed children retain scope, semantics and subscriptions across reorder" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(70, 1)
  let children : KeyedChildren[Int, String, TestChild] = KeyedChildren::new(
    root, tree,
  )
  let created = Ref(0)
  let updated = Ref(0)
  let disposed : Array[Int] = []
  let create = (owner : ChildOwner, key : Int, label : String) => {
    created.val += 1
    let reference = owner.add_input(label, "").unwrap()
    let name = @reactive.Signal::new(owner.scope(), label)
    let _ = @reactive.Binding::new(owner.scope(), () => name.get(), value => {
      ignore(@semantics.set_name(tree, reference, value))
    })
    owner
    .scope()
    .on_dispose(() => {
      if @semantics.node(tree, reference) is Err(_) {
        abort("listener cleanup ran after semantic target removal")
      }
      disposed.push(key)
    })
    TestChild::{ owner, reference, name, }
  }
  let update = (child : TestChild, label : String) => {
    updated.val += 1
    child.name.set(label)
  }
  assert_true(
    children.reconcile(
      [{ key: 1, props: "one", }, { key: 2, props: "two", }],
      create,
      update,
    ),
  )
  let first = children.get(1).unwrap()
  let second = children.get(2).unwrap()
  assert_eq(created.val, 2)
  assert_eq(updated.val, 0)
  assert_false(
    children.reconcile(
      [{ key: 1, props: "one", }, { key: 2, props: "two", }],
      create,
      update,
    ),
  )
  assert_true(
    children.reconcile(
      [{ key: 2, props: "two", }, { key: 1, props: "one", }],
      create,
      update,
    ),
  )
  assert_eq(created.val, 2)
  assert_eq(updated.val, 0)
  assert_eq(children.ordered()[0].reference, second.reference)
  assert_eq(children.ordered()[1].reference, first.reference)
  assert_eq(
    children.for_reference(first.reference).unwrap().owner.generation(),
    first.owner.generation(),
  )
  assert_true(
    children.reconcile(
      [{ key: 2, props: "TWO", }, { key: 1, props: "one", }],
      create,
      update,
    ),
  )
  assert_eq(created.val, 2)
  assert_eq(updated.val, 1)
  assert_eq(@semantics.node(tree, second.reference).unwrap().name, "TWO")
  assert_eq(@semantics.node(tree, first.reference).unwrap().name, "one")
  assert_eq(disposed, [])
  root.dispose()
  assert_eq(disposed, [2, 1])
  assert_true(@semantics.node(tree, first.reference) is Err(_))
  assert_true(@semantics.node(tree, second.reference) is Err(_))
  assert_true(children.ordered().is_empty())
  ignore(@semantics.dispose(tree))
}

///|
test "removed key revokes old reference before same-key recreation" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(71, 1)
  let children : KeyedChildren[Int, Int, TestChild] = KeyedChildren::new(
    root, tree,
  )
  let cleanup : Array[String] = []
  let create = (owner : ChildOwner, key : Int, props : Int) => {
    let reference = owner.add_input("Item " + key.to_string(), "old").unwrap()
    let name = @reactive.Signal::new(owner.scope(), "Item " + props.to_string())
    let nested = owner.scope().child()
    nested.on_dispose(() => cleanup.push("nested"))
    owner.scope().on_dispose(() => cleanup.push("owner"))
    TestChild::{ owner, reference, name, }
  }
  let update = (_ : TestChild, _ : Int) => ()
  assert_true(children.reconcile([{ key: 1, props: 1, }], create, update))
  let old = children.get(1).unwrap()
  assert_eq(@semantics.focus(tree, old.reference), "")
  assert_true(children.clear())
  assert_false(children.clear())
  assert_eq(cleanup, ["nested", "owner"])
  assert_true(children.for_reference(old.reference) is None)
  assert_true(@semantics.node(tree, old.reference) is Err(_))
  assert_true(children.reconcile([{ key: 1, props: 1, }], create, update))
  let fresh = children.get(1).unwrap()
  assert_true(fresh.owner.generation() != old.owner.generation())
  assert_true(fresh.reference != old.reference)
  assert_false(@semantics.node(tree, fresh.reference).unwrap().focused)
  assert_true(children.for_reference(old.reference) is None)
  assert_eq(
    children.for_reference(fresh.reference).unwrap().reference,
    fresh.reference,
  )
  fresh.owner.scope().dispose()
  assert_true(children.get(1) is None)
  assert_true(children.ordered().is_empty())
  assert_true(children.reconcile([{ key: 1, props: 1, }], create, update))
  assert_true(
    children.get(1).unwrap().owner.generation() != fresh.owner.generation(),
  )
  root.dispose()
  ignore(@semantics.dispose(tree))
}

///|
async test "removing a child rejects its late task result" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(72, 1)
  let children : KeyedChildren[Int, Int, @reactive_task.Source[Int, Int]] = KeyedChildren::new(
    root, tree,
  )
  let control = @task.task_control(_ => ())
  let create = (owner : ChildOwner, _ : Int, _ : Int) => {
    ignore(owner.add_button("Run").unwrap())
    let source : @reactive_task.Source[Int, Int] = @reactive_task.Source::new(
      owner.scope(),
    )
    if !source.connect(control) {
      abort("child Source did not connect")
    }
    source
  }
  assert_true(children.reconcile([{ key: 1, props: 0, }], create, (_, _) => ()))
  let old = children.get(1).unwrap()
  let request = old
    .replace(1, @reactive_task.Cycle::new(), false, () => 5)
    .unwrap()
  request.invalidate()
  let late = request.prepare().unwrap().run()
  assert_true(children.clear())
  assert_eq(late.apply(), @task.Rejected)
  assert_true(children.reconcile([{ key: 1, props: 0, }], create, (_, _) => ()))
  let fresh = children.get(1).unwrap()
  let new_request = fresh
    .replace(1, @reactive_task.Cycle::new(), false, () => 6)
    .unwrap()
  new_request.invalidate()
  assert_eq(new_request.prepare().unwrap().run().apply(), @task.Changed)
  root.dispose()
  ignore(@semantics.dispose(tree))
}
