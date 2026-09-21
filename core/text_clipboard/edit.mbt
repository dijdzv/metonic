///|
pub(all) enum Action {
  Copy
  Cut
  Paste
} derive(Debug, Eq)

///|
pub(all) struct Backend {
  read : () -> Result[String?, String]
  write : (String) -> Result[Unit, String]
}

///|
pub(all) enum Outcome {
  Unchanged
  Edited
} derive(Debug, Eq)

///|
fn selection_matches(tree : @semantics.Tree, before : @semantics.Node) -> Bool {
  match @semantics.node(tree, before.reference) {
    Err(_) => false
    Ok(after) =>
      after.enabled &&
      after.focused &&
      after.value == before.value &&
      after.selection_start == before.selection_start &&
      after.selection_end == before.selection_end &&
      after.selection_anchor == before.selection_anchor
  }
}

///|
fn replace(
  tree : @semantics.Tree,
  before : @semantics.Node,
  text : String,
) -> Result[Outcome, String] {
  if !selection_matches(tree, before) {
    return Err("stale_selection")
  }
  let revision = @semantics.revision(tree)
  let error = @semantics.replace_selection(tree, before.reference, text)
  if error != "" {
    Err(error)
  } else {
    Ok(if @semantics.revision(tree) == revision { Unchanged } else { Edited })
  }
}

///|
pub fn apply(
  tree : @semantics.Tree,
  target : @semantics.NodeRef,
  action : Action,
  backend : Backend,
  single_line? : Bool = false,
  composing? : Bool = false,
) -> Result[Outcome, String] {
  let node = match @semantics.node(tree, target) {
    Ok(node) => node
    Err(error) => return Err(error)
  }
  if node.role != @semantics.TextInput {
    return Err("unsupported_action")
  }
  if !node.enabled {
    return Err("disabled")
  }
  if !node.focused {
    return Err("not_focused")
  }
  if composing {
    return Ok(Unchanged)
  }
  match action {
    Copy | Cut => {
      if node.selection_start == node.selection_end {
        return Ok(Unchanged)
      }
      let selected = node.value[node.selection_start:node.selection_end].to_owned()
      if selected.contains("\u0000") {
        return Err("invalid_clipboard_text")
      }
      match (backend.write)(selected) {
        Err(error) => Err(error)
        Ok(_) =>
          if action == Cut {
            replace(tree, node, "")
          } else {
            Ok(Unchanged)
          }
      }
    }
    Paste =>
      match (backend.read)() {
        Err(error) => Err(error)
        Ok(None) => Ok(Unchanged)
        Ok(Some(text)) => {
          if text.contains("\u0000") {
            return Err("invalid_clipboard_text")
          }
          let normalized = text
            .replace_all(old="\r\n", new="\n")
            .replace_all(old="\r", new="\n")
          let inserted = if single_line {
            normalized.replace_all(old="\n", new="")
          } else {
            normalized
          }
          if inserted == "" {
            Ok(Unchanged)
          } else {
            replace(tree, node, inserted)
          }
        }
      }
  }
}
