#include <windows.h>
#include <oleauto.h>
#include <uiautomationcore.h>
#include <uiautomationcoreapi.h>
#include <stdint.h>

/* The SDK owns the cache layout and VARIANT-to-node conversion. */
uintptr_t metonic_uia_navigate(uintptr_t parent, int32_t direction) {
  struct UiaCondition condition = {ConditionType_True};
  struct UiaCacheRequest request = {&condition, TreeScope_Element, NULL, 0,
      NULL, 0, AutomationElementMode_Full};
  SAFEARRAY *data = NULL;
  BSTR structure = NULL;
  HUIANODE node = NULL;
  HRESULT result = UiaNavigate((HUIANODE)parent, direction, &condition,
      &request, &data, &structure);
  if (SUCCEEDED(result) && data) {
    LONG indices[2] = {0, 0};
    VARIANT value;
    VariantInit(&value);
    if (SUCCEEDED(SafeArrayGetElement(data, indices, &value))) {
      UiaHUiaNodeFromVariant(&value, &node);
      VariantClear(&value);
    }
  }
  if (data) SafeArrayDestroy(data);
  SysFreeString(structure);
  return (uintptr_t)node;
}
