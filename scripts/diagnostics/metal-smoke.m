#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>

// Standalone system test. Does not load Wine, the game or account data.
int main(int argc, const char **argv) {
    @autoreleasepool {
        BOOL windowed = argc > 1 && strcmp(argv[1], "--windowed") == 0;
        NSUInteger frames = 300;
        if (argc == 4 && strcmp(argv[2], "--frames") == 0) {
            long count = strtol(argv[3], NULL, 10);
            if (count < 1 || count > 600) return 6;
            frames = (NSUInteger)count;
        }
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { fprintf(stderr, "METAL_NO_DEVICE\n"); return 1; }
        id<MTLCommandQueue> queue = [device newCommandQueue];
        MTLTextureDescriptor *descriptor = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
            width:64 height:64 mipmapped:NO];
        descriptor.usage = MTLTextureUsageRenderTarget;
        id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
        NSWindow *window = nil;
        CAMetalLayer *layer = nil;
        if (windowed) {
            [NSApplication sharedApplication];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 240, 160)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            window.releasedWhenClosed = NO;
            window.title = @"OW120 图形检查";
            layer = [CAMetalLayer layer]; layer.device = device;
            layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            layer.drawableSize = CGSizeMake(240, 160);
            window.contentView.wantsLayer = YES;
            window.contentView.layer = layer;
            [window orderFront:nil];
        }
        if (!queue || !texture) { fprintf(stderr, "METAL_RESOURCE_FAILED\n"); return 2; }
        for (NSUInteger frame = 0; frame < frames; frame++) {
            @autoreleasepool {
                MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
                id<CAMetalDrawable> drawable = windowed ? [layer nextDrawable] : nil;
                if (windowed && !drawable) { fprintf(stderr, "METAL_DRAWABLE_FAILED\n"); return 5; }
                pass.colorAttachments[0].texture = drawable ? drawable.texture : texture;
                pass.colorAttachments[0].loadAction = MTLLoadActionClear;
                pass.colorAttachments[0].storeAction = MTLStoreActionStore;
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0.2, 0.4, 0.6, 1.0);
                id<MTLCommandBuffer> buffer = [queue commandBuffer];
                id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
                if (!encoder) { fprintf(stderr, "METAL_ENCODER_FAILED\n"); return 3; }
                [encoder endEncoding];
                if (drawable) [buffer presentDrawable:drawable];
                [buffer commit]; [buffer waitUntilCompleted];
                if (windowed) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, true);
                if (buffer.status != MTLCommandBufferStatusCompleted) {
                    fprintf(stderr, "METAL_COMMAND_FAILED %s\n", buffer.error.localizedDescription.UTF8String);
                    return 4;
                }
            }
        }
        [window close];
        printf("METAL_COMMANDS_OK count=%lu device=%s mode=%s\n", (unsigned long)frames, device.name.UTF8String, windowed ? "windowed" : "offscreen");
    }
    return 0;
}
