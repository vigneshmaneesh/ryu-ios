#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <malloc.h>

#include <switch.h>
#include <deko3d.h>

// Define the desired number of framebuffers
#define FB_NUM 2

// Keep the first iOS guest workload small at 360p.
#define FB_WIDTH  640
#define FB_HEIGHT 360

// Remove above and uncomment below for 1080p
//#define FB_WIDTH  1920
//#define FB_HEIGHT 1080

// Define the size of the memory block that will hold code
#define CODEMEMSIZE (64*1024)

// Define the size of the memory block that will hold command lists
#define CMDMEMSIZE (16*1024)

static DkDevice g_device;
static DkMemBlock g_framebufferMemBlock;
static DkImage g_framebuffers[FB_NUM];
static DkSwapchain g_swapchain;

static DkMemBlock g_codeMemBlock;
static uint32_t g_codeMemOffset;
static DkShader g_vertexShader;
static DkShader g_fragmentShader;

static DkMemBlock g_cmdbufMemBlock;
static DkCmdBuf g_cmdbuf;
static DkCmdList g_cmdsBindFramebuffer[FB_NUM];
static DkCmdList g_cmdsRender;

static DkQueue g_renderQueue;
static DkMemBlock g_frameMem;
static DkCmdBuf g_frameCmd[FB_NUM];
static PadState g_pad;
static float g_x = 320, g_y = 220, g_targetX = 460, g_targetY = 220;
static unsigned g_score;
static AudioOutBuffer g_audioBuffers[4];
static bool g_audioBusy[4], g_audioReady;
static uint32_t g_random = 41;

static void marker(const char* text) { svcOutputDebugString(text, strlen(text)); }
static void audioReclaim(void)
{
    if (!g_audioReady) return;
    AudioOutBuffer* released;
    u32 count;
    while (R_SUCCEEDED(audoutGetReleasedAudioOutBuffer(&released, &count)) && count) {
        for (unsigned i = 0; i < 4; i++) if (released == &g_audioBuffers[i]) g_audioBusy[i] = false;
    }
}
static void beep(void)
{
    if (!g_audioReady) return;
    audioReclaim();
    for (unsigned i = 0; i < 4; i++) if (!g_audioBusy[i]) {
        int16_t* pcm = g_audioBuffers[i].buffer;
        for (unsigned sample = 0; sample < 4800; sample++) {
            float envelope = (1.0f - sample / 4800.0f);
            int16_t value = (int16_t)(4000 * envelope * sinf(6.2831853f * (440 + (g_score % 8) * 70) * sample / 48000));
            pcm[sample * 2] = pcm[sample * 2 + 1] = value;
        }
        if (R_SUCCEEDED(audoutAppendAudioOutBuffer(&g_audioBuffers[i]))) g_audioBusy[i] = true;
        return;
    }
}

// Simple function for loading a shader from the filesystem
static void loadShader(DkShader* pShader, const char* path)
{
    // Open the file, and retrieve its size
    FILE* f = fopen(path, "rb");
    fseek(f, 0, SEEK_END);
    uint32_t size = ftell(f);
    rewind(f);

    // Look for a spot in the code memory block for loading this shader. Note that
    // we are just using a simple incremental offset; this isn't a general purpose
    // allocation algorithm.
    uint32_t codeOffset = g_codeMemOffset;
    g_codeMemOffset += (size + DK_SHADER_CODE_ALIGNMENT - 1) &~ (DK_SHADER_CODE_ALIGNMENT - 1);

    // Read the file into memory, and close the file
    fread((uint8_t*)dkMemBlockGetCpuAddr(g_codeMemBlock) + codeOffset, size, 1, f);
    fclose(f);

    // Initialize the user provided shader object with the code we've just loaded
    DkShaderMaker shaderMaker;
    dkShaderMakerDefaults(&shaderMaker, g_codeMemBlock, codeOffset);
    dkShaderInitialize(pShader, &shaderMaker);
}

// This function creates all the necessary graphical resources.
static void graphicsInitialize(void)
{
    // Create the device, which is the root object
    DkDeviceMaker deviceMaker;
    dkDeviceMakerDefaults(&deviceMaker);
    g_device = dkDeviceCreate(&deviceMaker);

    // Calculate layout for the framebuffers
    DkImageLayoutMaker imageLayoutMaker;
    dkImageLayoutMakerDefaults(&imageLayoutMaker, g_device);
    imageLayoutMaker.flags = DkImageFlags_UsageRender | DkImageFlags_UsagePresent | DkImageFlags_HwCompression;
    imageLayoutMaker.format = DkImageFormat_RGBA8_Unorm;
    imageLayoutMaker.dimensions[0] = FB_WIDTH;
    imageLayoutMaker.dimensions[1] = FB_HEIGHT;

    // Calculate layout for the framebuffers
    DkImageLayout framebufferLayout;
    dkImageLayoutInitialize(&framebufferLayout, &imageLayoutMaker);

    // Retrieve necessary size and alignment for the framebuffers
    uint32_t framebufferSize  = dkImageLayoutGetSize(&framebufferLayout);
    uint32_t framebufferAlign = dkImageLayoutGetAlignment(&framebufferLayout);
    framebufferSize = (framebufferSize + framebufferAlign - 1) &~ (framebufferAlign - 1);

    // Create a memory block that will host the framebuffers
    DkMemBlockMaker memBlockMaker;
    dkMemBlockMakerDefaults(&memBlockMaker, g_device, FB_NUM*framebufferSize);
    memBlockMaker.flags = DkMemBlockFlags_GpuCached | DkMemBlockFlags_Image;
    g_framebufferMemBlock = dkMemBlockCreate(&memBlockMaker);

    // Initialize the framebuffers with the layout and backing memory we've just created
    DkImage const* swapchainImages[FB_NUM];
    for (unsigned i = 0; i < FB_NUM; i ++)
    {
        swapchainImages[i] = &g_framebuffers[i];
        dkImageInitialize(&g_framebuffers[i], &framebufferLayout, g_framebufferMemBlock, i*framebufferSize);
    }

    // Create a swapchain out of the framebuffers we've just initialized
    DkSwapchainMaker swapchainMaker;
    dkSwapchainMakerDefaults(&swapchainMaker, g_device, nwindowGetDefault(), swapchainImages, FB_NUM);
    g_swapchain = dkSwapchainCreate(&swapchainMaker);

    // Create a memory block onto which we will load shader code
    dkMemBlockMakerDefaults(&memBlockMaker, g_device, CODEMEMSIZE);
    memBlockMaker.flags = DkMemBlockFlags_CpuUncached | DkMemBlockFlags_GpuCached | DkMemBlockFlags_Code;
    g_codeMemBlock = dkMemBlockCreate(&memBlockMaker);
    g_codeMemOffset = 0;

    // Load our shaders (both vertex and fragment)
    loadShader(&g_vertexShader, "romfs:/shaders/triangle_vsh.dksh");
    loadShader(&g_fragmentShader, "romfs:/shaders/color_fsh.dksh");

    // Create a memory block which will be used for recording command lists using a command buffer
    dkMemBlockMakerDefaults(&memBlockMaker, g_device, CMDMEMSIZE);
    memBlockMaker.flags = DkMemBlockFlags_CpuUncached | DkMemBlockFlags_GpuCached;
    g_cmdbufMemBlock = dkMemBlockCreate(&memBlockMaker);

    // Create a command buffer object
    DkCmdBufMaker cmdbufMaker;
    dkCmdBufMakerDefaults(&cmdbufMaker, g_device);
    g_cmdbuf = dkCmdBufCreate(&cmdbufMaker);

    // Feed our memory to the command buffer so that we can start recording commands
    dkCmdBufAddMemory(g_cmdbuf, g_cmdbufMemBlock, 0, CMDMEMSIZE);

    // Generate a command list for each framebuffer, which will bind each of them as a render target
    for (unsigned i = 0; i < FB_NUM; i ++)
    {
        DkImageView imageView;
        dkImageViewDefaults(&imageView, &g_framebuffers[i]);
        dkCmdBufBindRenderTarget(g_cmdbuf, &imageView, NULL);
        g_cmdsBindFramebuffer[i] = dkCmdBufFinishList(g_cmdbuf);
    }

    // Declare structs that will be used for binding state
    DkShader const* shaders[] = { &g_vertexShader, &g_fragmentShader };
    DkRasterizerState rasterizerState;
    DkColorState colorState;
    DkColorWriteState colorWriteState;

    // Initialize state structs with the deko3d defaults
    dkRasterizerStateDefaults(&rasterizerState);
    dkColorStateDefaults(&colorState);
    dkColorWriteStateDefaults(&colorWriteState);

    // Generate the main rendering command list
    dkCmdBufBindShaders(g_cmdbuf, DkStageFlag_GraphicsMask, shaders, sizeof(shaders)/sizeof(shaders[0]));
    dkCmdBufBindRasterizerState(g_cmdbuf, &rasterizerState);
    dkCmdBufBindColorState(g_cmdbuf, &colorState);
    dkCmdBufBindColorWriteState(g_cmdbuf, &colorWriteState);
    dkCmdBufDraw(g_cmdbuf, DkPrimitive_Triangles, 3, 1, 0, 0);
    g_cmdsRender = dkCmdBufFinishList(g_cmdbuf);

    // Create a queue, to which we will submit our command lists
    DkQueueMaker queueMaker;
    dkQueueMakerDefaults(&queueMaker, g_device);
    queueMaker.flags = DkQueueFlags_Graphics;
    g_renderQueue = dkQueueCreate(&queueMaker);
    dkMemBlockMakerDefaults(&memBlockMaker, g_device, FB_NUM * CMDMEMSIZE);
    memBlockMaker.flags = DkMemBlockFlags_CpuUncached | DkMemBlockFlags_GpuCached;
    g_frameMem = dkMemBlockCreate(&memBlockMaker);
    for (unsigned i = 0; i < FB_NUM; i++) g_frameCmd[i] = dkCmdBufCreate(&cmdbufMaker);
}

// This function is to be called at each frame, and it is in charge of rendering.
static void graphicsUpdate(void)
{
    // Acquire a framebuffer from the swapchain (and wait for it to be available)
    int slot = dkQueueAcquireImage(g_renderQueue, g_swapchain);

    // Reuse this slot's command memory only after its image has been acquired.
    DkCmdBuf cmd = g_frameCmd[slot];
    dkCmdBufClear(cmd);
    dkCmdBufAddMemory(cmd, g_frameMem, slot * CMDMEMSIZE, CMDMEMSIZE);
    dkCmdBufCallList(cmd, g_cmdsBindFramebuffer[slot]);
    DkScissor whole = { 0, 0, FB_WIDTH, FB_HEIGHT };
    dkCmdBufSetScissors(cmd, 0, &whole, 1);
    dkCmdBufClearColorFloat(cmd, 0, DkColorMask_RGBA, 0.025f, 0.055f, 0.105f, 1);
    DkViewport ship = { g_x - 15, g_y - 15, 30, 30, 0, 1 };
    dkCmdBufSetViewports(cmd, 0, &ship, 1);
    dkCmdBufCallList(cmd, g_cmdsRender);
    DkViewport target = { g_targetX - 10, g_targetY - 10, 20, 20, 0, 1 };
    dkCmdBufSetViewports(cmd, 0, &target, 1);
    dkCmdBufCallList(cmd, g_cmdsRender);
    // Score pips are rendered by the guest GPU, along the top edge.
    for (unsigned pip = 0; pip < (g_score % 20); pip++) {
        DkScissor box = { 12 + pip * 15, 12, 10, 7 };
        dkCmdBufSetScissors(cmd, 0, &box, 1);
        dkCmdBufClearColorFloat(cmd, 0, DkColorMask_RGBA, 0.1f, 0.9f, 0.65f, 1);
    }
    dkQueueSubmitCommands(g_renderQueue, dkCmdBufFinishList(cmd));

    // Now that we are done rendering, present it to the screen
    dkQueuePresentImage(g_renderQueue, g_swapchain, slot);
}

// This function destroys the graphical resources created by graphicsInitialize.
static void graphicsExit(void)
{
    // Make sure the rendering queue is idle before destroying anything
    dkQueueWaitIdle(g_renderQueue);

    // Destroy all the resources we've created
    dkQueueDestroy(g_renderQueue);
    for (unsigned i = 0; i < FB_NUM; i++) dkCmdBufDestroy(g_frameCmd[i]);
    dkMemBlockDestroy(g_frameMem);
    dkCmdBufDestroy(g_cmdbuf);
    dkMemBlockDestroy(g_cmdbufMemBlock);
    dkMemBlockDestroy(g_codeMemBlock);
    dkSwapchainDestroy(g_swapchain);
    dkMemBlockDestroy(g_framebufferMemBlock);
    dkDeviceDestroy(g_device);
}

// Main entrypoint
int main(int argc, char* argv[])
{
    (void)argc; (void)argv;
    romfsInit();
    graphicsInitialize();
    padConfigureInput(1, HidNpadStyleSet_NpadStandard);
    padInitializeDefault(&g_pad);
    hidInitializeTouchScreen();
    Result audioResult = audoutInitialize();
    if (R_SUCCEEDED(audioResult)) {
        g_audioReady = true;
        for (unsigned i = 0; i < 4; i++) {
            g_audioBuffers[i].buffer = memalign(0x1000, 0x5000);
            g_audioBuffers[i].buffer_size = 0x5000;
            g_audioBuffers[i].data_size = 4800 * 4;
            if (!g_audioBuffers[i].buffer) g_audioReady = false;
        }
        if (g_audioReady && R_FAILED(audoutStartAudioOut())) g_audioReady = false;
    }
    marker(g_audioReady ? "RYU_PLAY: audio ready" : "RYU_PLAY: audio unavailable");
    bool inputSeen = false, touchSeen = false;
    unsigned frames = 0;
    while (appletMainLoop())
    {
        padUpdate(&g_pad);
        u64 keys = padGetButtons(&g_pad);
        u64 pressed = padGetButtonsDown(&g_pad);
        if (pressed & HidNpadButton_Plus) break;
        HidAnalogStickState stick = padGetStickPos(&g_pad, 0);
        HidTouchScreenState touch;
        hidGetTouchScreenStates(&touch, 1);
        if (!inputSeen && (keys || stick.x || stick.y || touch.count)) { marker("RYU_PLAY: input received through guest HID"); inputSeen = true; }
        if (!touchSeen && touch.count) { marker("RYU_PLAY: touch received through guest HID"); touchSeen = true; }
        float speed = (keys & HidNpadButton_A) ? 6 : 3;
        g_x += speed * stick.x / 32767;
        g_y -= speed * stick.y / 32767;
        if (keys & HidNpadButton_Left) g_x -= speed;
        if (keys & HidNpadButton_Right) g_x += speed;
        if (keys & HidNpadButton_Up) g_y -= speed;
        if (keys & HidNpadButton_Down) g_y += speed;
        if (touch.count) { g_x = touch.touches[0].x * 0.5f; g_y = touch.touches[0].y * 0.5f; }
        g_x = fminf(624, fmaxf(16, g_x)); g_y = fminf(344, fmaxf(34, g_y));
        if ((pressed & HidNpadButton_B)) { g_score = 0; g_x = 320; g_y = 220; g_targetX = 460; g_targetY = 220; }
        if ((pressed & HidNpadButton_A)) beep();
        float dx = g_x - g_targetX, dy = g_y - g_targetY;
        if (dx * dx + dy * dy < 22 * 22) {
            g_score++; beep();
            g_random = g_random * 1664525u + 1013904223u; g_targetX = 35 + (g_random % 570);
            g_random = g_random * 1664525u + 1013904223u; g_targetY = 50 + (g_random % 270);
            marker("RYU_PLAY: target collected");
        }
        audioReclaim();
        graphicsUpdate();
        frames++;
    }
    char summary[96];
    snprintf(summary, sizeof(summary), "RYU_PLAY: completed frames=%u score=%u input=%u", frames, g_score, inputSeen);
    marker(summary);
    if (R_SUCCEEDED(audioResult)) {
        audoutStopAudioOut(); audoutExit();
        for (unsigned i = 0; i < 4; i++) free(g_audioBuffers[i].buffer);
    }
    graphicsExit();
    romfsExit();
    return 0;
}
