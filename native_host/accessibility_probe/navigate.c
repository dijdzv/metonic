#include <windows.h>
#include <oleauto.h>
#include <uiautomationcore.h>
#include <uiautomationcoreapi.h>
#include <stdint.h>

/* The SDK owns the cache layout and VARIANT-to-node conversion. */
static uintptr_t take_cached_node(HRESULT result, SAFEARRAY *data, BSTR structure) {
  HUIANODE node = NULL;
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

uintptr_t metonic_uia_navigate(uintptr_t parent, int32_t direction) {
  struct UiaCondition condition = {ConditionType_True};
  struct UiaCacheRequest request = {&condition, TreeScope_Element, NULL, 0,
      NULL, 0, AutomationElementMode_Full};
  SAFEARRAY *data = NULL;
  BSTR structure = NULL;
  HRESULT result = UiaNavigate((HUIANODE)parent, direction, &condition,
      &request, &data, &structure);
  return take_cached_node(result, data, structure);
}

uintptr_t metonic_uia_focused_node(void) {
  struct UiaCondition condition = {ConditionType_True};
  struct UiaCacheRequest request = {&condition, TreeScope_Element, NULL, 0,
      NULL, 0, AutomationElementMode_Full};
  SAFEARRAY *data = NULL;
  BSTR structure = NULL;
  HRESULT result = UiaNodeFromFocus(&request, &data, &structure);
  return take_cached_node(result, data, structure);
}

uintptr_t metonic_uia_selected_range(uintptr_t provider) {
  SAFEARRAY *ranges = NULL;
  HUIATEXTRANGE range = NULL;
  if (SUCCEEDED(TextPattern_GetSelection((HUIAPATTERNOBJECT)provider, &ranges)) && ranges) {
    LONG first = 0, last = -1;
    VARTYPE type = VT_EMPTY;
    if (SafeArrayGetDim(ranges) == 1 &&
        SUCCEEDED(SafeArrayGetVartype(ranges, &type)) && type == VT_VARIANT &&
        SUCCEEDED(SafeArrayGetLBound(ranges, 1, &first)) &&
        SUCCEEDED(SafeArrayGetUBound(ranges, 1, &last)) && first == last) {
      VARIANT value;
      VariantInit(&value);
      if (SUCCEEDED(SafeArrayGetElement(ranges, &first, &value))) {
        UiaHTextRangeFromVariant(&value, &range);
      }
      VariantClear(&value);
    }
  }
  if (ranges) SafeArrayDestroy(ranges);
  return (uintptr_t)range;
}
