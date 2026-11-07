// Independent backend conformance. This is not the emulated Switch GPU.
#include <vulkan/vulkan.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t memory_type(VkPhysicalDevice gpu, uint32_t bits, VkMemoryPropertyFlags flags) {
    VkPhysicalDeviceMemoryProperties properties;
    vkGetPhysicalDeviceMemoryProperties(gpu, &properties);
    for (uint32_t i = 0; i < properties.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (properties.memoryTypes[i].propertyFlags & flags) == flags) return i;
    return UINT32_MAX;
}

int ryu_vulkan_probe(char *report, size_t capacity) {
    if (report == NULL || capacity < 2) return -1;
    report[0] = '\0';
    VkInstance instance = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkImage image = VK_NULL_HANDLE;
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory image_memory = VK_NULL_HANDLE, buffer_memory = VK_NULL_HANDLE;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    void *mapped = NULL;
    int success = 0;
    const char *step = "instance";
    VkResult result = VK_SUCCESS;
#define TRY(operation) do { result = (operation); if (result != VK_SUCCESS) goto cleanup; } while (0)
    // Direct MoltenVK linkage on iOS can omit the loader's portability-enumeration
    // extension. Enable its flag only when this instance implementation advertises it.
    uint32_t instance_extension_count = 0;
    TRY(vkEnumerateInstanceExtensionProperties(NULL, &instance_extension_count, NULL));
    VkExtensionProperties *instance_extensions = calloc(instance_extension_count, sizeof(*instance_extensions));
    if (instance_extensions == NULL) { result = VK_ERROR_OUT_OF_HOST_MEMORY; goto cleanup; }
    result = vkEnumerateInstanceExtensionProperties(NULL, &instance_extension_count, instance_extensions);
    bool enumerate_portability = false;
    for (uint32_t i = 0; i < instance_extension_count; i++)
        if (strcmp(instance_extensions[i].extensionName, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) == 0)
            enumerate_portability = true;
    free(instance_extensions);
    if (result != VK_SUCCESS) goto cleanup;
    const char *extensions[] = {VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME};
    VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Ryu iOS backend check", .apiVersion = VK_API_VERSION_1_1};
    VkInstanceCreateInfo create_instance = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .flags = enumerate_portability ? VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR : 0, .pApplicationInfo = &app,
        .enabledExtensionCount = enumerate_portability ? 1 : 0, .ppEnabledExtensionNames = extensions};
    TRY(vkCreateInstance(&create_instance, NULL, &instance));
    step = "physical device";
    uint32_t count = 0;
    TRY(vkEnumeratePhysicalDevices(instance, &count, NULL));
    if (count == 0) { result = VK_ERROR_INITIALIZATION_FAILED; goto cleanup; }
    VkPhysicalDevice *gpus = calloc(count, sizeof(*gpus));
    if (gpus == NULL) { result = VK_ERROR_OUT_OF_HOST_MEMORY; goto cleanup; }
    result = vkEnumeratePhysicalDevices(instance, &count, gpus);
    VkPhysicalDevice gpu = gpus[0];
    free(gpus);
    if (result != VK_SUCCESS) goto cleanup;
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(gpu, &properties);
    uint32_t queue_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(gpu, &queue_count, NULL);
    VkQueueFamilyProperties *queues = calloc(queue_count, sizeof(*queues));
    if (queues == NULL) { result = VK_ERROR_OUT_OF_HOST_MEMORY; goto cleanup; }
    vkGetPhysicalDeviceQueueFamilyProperties(gpu, &queue_count, queues);
    uint32_t family = UINT32_MAX;
    for (uint32_t i = 0; i < queue_count; i++)
        if (queues[i].queueCount > 0 && (queues[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) { family = i; break; }
    free(queues);
    if (family == UINT32_MAX) { result = VK_ERROR_FEATURE_NOT_PRESENT; goto cleanup; }
    step = "logical device";
    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = family, .queueCount = 1, .pQueuePriorities = &priority};
    // Portability subset must be enabled when advertised by a portability driver.
    uint32_t extension_count = 0;
    TRY(vkEnumerateDeviceExtensionProperties(gpu, NULL, &extension_count, NULL));
    VkExtensionProperties *device_extensions = calloc(extension_count, sizeof(*device_extensions));
    if (device_extensions == NULL) { result = VK_ERROR_OUT_OF_HOST_MEMORY; goto cleanup; }
    result = vkEnumerateDeviceExtensionProperties(gpu, NULL, &extension_count, device_extensions);
    bool portability = false;
    for (uint32_t i = 0; i < extension_count; i++)
        if (strcmp(device_extensions[i].extensionName, "VK_KHR_portability_subset") == 0) portability = true;
    free(device_extensions);
    if (result != VK_SUCCESS) goto cleanup;
    const char *subset = "VK_KHR_portability_subset";
    VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1, .pQueueCreateInfos = &queue_info,
        .enabledExtensionCount = portability ? 1 : 0, .ppEnabledExtensionNames = &subset};
    TRY(vkCreateDevice(gpu, &device_info, NULL, &device));
    VkQueue queue;
    vkGetDeviceQueue(device, family, 0, &queue);
    step = "image allocation";
    VkImageCreateInfo image_info = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R8G8B8A8_UNORM,
        .extent = {4, 4, 1}, .mipLevels = 1, .arrayLayers = 1, .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL, .usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED};
    TRY(vkCreateImage(device, &image_info, NULL, &image));
    VkMemoryRequirements requirements;
    vkGetImageMemoryRequirements(device, image, &requirements);
    uint32_t image_type = memory_type(gpu, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (image_type == UINT32_MAX) { result = VK_ERROR_FEATURE_NOT_PRESENT; goto cleanup; }
    VkMemoryAllocateInfo allocate = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = requirements.size, .memoryTypeIndex = image_type};
    TRY(vkAllocateMemory(device, &allocate, NULL, &image_memory));
    TRY(vkBindImageMemory(device, image, image_memory, 0));
    step = "readback allocation";
    VkBufferCreateInfo buffer_info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = 64, .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
    TRY(vkCreateBuffer(device, &buffer_info, NULL, &buffer));
    vkGetBufferMemoryRequirements(device, buffer, &requirements);
    uint32_t buffer_type = memory_type(gpu, requirements.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (buffer_type == UINT32_MAX) { result = VK_ERROR_FEATURE_NOT_PRESENT; goto cleanup; }
    allocate.allocationSize = requirements.size;
    allocate.memoryTypeIndex = buffer_type;
    TRY(vkAllocateMemory(device, &allocate, NULL, &buffer_memory));
    TRY(vkBindBufferMemory(device, buffer, buffer_memory, 0));
    step = "command encoding";
    VkCommandPoolCreateInfo pool_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = family};
    TRY(vkCreateCommandPool(device, &pool_info, NULL, &pool));
    VkCommandBufferAllocateInfo command_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
    VkCommandBuffer command;
    TRY(vkAllocateCommandBuffers(device, &command_info, &command));
    VkCommandBufferBeginInfo begin = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
    TRY(vkBeginCommandBuffer(command, &begin));
    VkImageSubresourceRange range = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT, .levelCount = 1, .layerCount = 1};
    VkImageMemoryBarrier barrier = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = image, .subresourceRange = range};
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, NULL, 0, NULL, 1, &barrier);
    VkClearColorValue color = {.float32 = {0.25f, 0.5f, 0.75f, 1.0f}};
    vkCmdClearColorImage(command, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &range);
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, NULL, 0, NULL, 1, &barrier);
    VkBufferImageCopy copy = {.imageSubresource = {.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT, .layerCount = 1},
        .imageExtent = {4, 4, 1}};
    vkCmdCopyImageToBuffer(command, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer, 1, &copy);
    VkBufferMemoryBarrier host_barrier = {.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .buffer = buffer, .size = VK_WHOLE_SIZE};
    vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT,
        0, 0, NULL, 1, &host_barrier, 0, NULL);
    TRY(vkEndCommandBuffer(command));
    VkFenceCreateInfo fence_info = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    TRY(vkCreateFence(device, &fence_info, NULL, &fence));
    VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &command};
    step = "GPU submission";
    TRY(vkQueueSubmit(queue, 1, &submit, fence));
    TRY(vkWaitForFences(device, 1, &fence, VK_TRUE, 5000000000ULL));
    step = "GPU pixel verification";
    TRY(vkMapMemory(device, buffer_memory, 0, 64, 0, &mapped));
    const int expected[] = {64, 128, 191, 255};
    for (size_t i = 0; i < 64; i++) {
        int difference = (int)((uint8_t *)mapped)[i] - expected[i % 4];
        if (difference < -1 || difference > 1) { result = VK_ERROR_UNKNOWN; goto cleanup; }
    }
    snprintf(report, capacity, "PASS MoltenVK / Metal GPU: %s\n16 RGBA pixels cleared and read back correctly.\nEmulated Switch graphics are not yet integrated.", properties.deviceName);
    success = 1;
cleanup:
    if (device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(device);
        if (mapped != NULL) vkUnmapMemory(device, buffer_memory);
        if (fence != VK_NULL_HANDLE) vkDestroyFence(device, fence, NULL);
        if (pool != VK_NULL_HANDLE) vkDestroyCommandPool(device, pool, NULL);
        if (buffer != VK_NULL_HANDLE) vkDestroyBuffer(device, buffer, NULL);
        if (buffer_memory != VK_NULL_HANDLE) vkFreeMemory(device, buffer_memory, NULL);
        if (image != VK_NULL_HANDLE) vkDestroyImage(device, image, NULL);
        if (image_memory != VK_NULL_HANDLE) vkFreeMemory(device, image_memory, NULL);
        vkDestroyDevice(device, NULL);
    }
    if (instance != VK_NULL_HANDLE) vkDestroyInstance(instance, NULL);
    if (!success) snprintf(report, capacity, "FAIL Vulkan %s: result %d", step, (int)result);
    return success ? 0 : -1;
#undef TRY
}
