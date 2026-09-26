///|
extern "js" fn install_storage_test_window(mode : Int) -> Unit =
  #| (mode) => {
  #|   const data = new Map();
  #|   globalThis.window = {
  #|     get localStorage() {
  #|       if (mode === 1) {
  #|         const error = new Error('denied');
  #|         error.name = 'SecurityError';
  #|         throw error;
  #|       }
  #|       return {
  #|         getItem: key => data.get(key) ?? null,
  #|         setItem: (key, value) => {
  #|           if (mode === 2) {
  #|             const error = new Error('full');
  #|             error.name = 'QuotaExceededError';
  #|             throw error;
  #|           }
  #|           data.set(key, value);
  #|         },
  #|       };
  #|     },
  #|   };
  #| }

///|
async test "browser snapshot adapter maps typed storage outcomes" {
  install_storage_test_window(0)
  let snapshot = @storage.text_snapshot("work-orders")
  assert_eq(snapshot.load(), Ok(None))
  assert_eq(snapshot.save("日本語😀"), Ok(()))
  assert_eq(snapshot.load(), Ok(Some("日本語😀")))
  install_storage_test_window(1)
  assert_eq(snapshot.load(), Err(@snapshot.AccessDenied))
  assert_eq(snapshot.save("draft"), Err(@snapshot.AccessDenied))
  install_storage_test_window(2)
  assert_eq(snapshot.save("draft"), Err(@snapshot.CapacityExceeded))
}
