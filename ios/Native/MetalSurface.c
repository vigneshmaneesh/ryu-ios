#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>
#include <stdint.h>

int ryu_create_metal_surface(void *instance_handle, void *layer, uint64_t *surface_handle) {
    VkInstance instance = (VkInstance)instance_handle;
    PFN_vkCreateMetalSurfaceEXT create = (PFN_vkCreateMetalSurfaceEXT)
        vkGetInstanceProcAddr(instance, "vkCreateMetalSurfaceEXT");
    if (create == NULL || layer == NULL || surface_handle == NULL) return VK_ERROR_EXTENSION_NOT_PRESENT;
    VkMetalSurfaceCreateInfoEXT info = {.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT, .pLayer = layer};
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkResult status = create(instance, &info, NULL, &surface);
    *surface_handle = (uint64_t)surface;
    return status;
}
