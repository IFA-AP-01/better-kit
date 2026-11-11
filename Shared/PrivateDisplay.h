// Private CoreGraphics / IOKit declarations. These exist on every macOS 14+ Apple Silicon system;
// BetterKit is distributed outside the App Store, so private API use is acceptable.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>

NS_ASSUME_NONNULL_BEGIN

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nullable) dispatch_queue_t queue;
@property (copy) NSString *name;
@property unsigned int maxPixelsHigh;
@property unsigned int maxPixelsWide;
@property CGSize sizeInMillimeters;
@property unsigned int productID;
@property unsigned int vendorID;
@property unsigned int serialNum;
@property (copy, nullable) void (^terminationHandler)(id _Nullable display, id _Nullable reason);
@property CGPoint redPrimary;
@property CGPoint greenPrimary;
@property CGPoint bluePrimary;
@property CGPoint whitePoint;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@property (readonly) NSUInteger width;
@property (readonly) NSUInteger height;
@property (readonly) double refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain) NSArray<CGVirtualDisplayMode *> *modes;
@property unsigned int hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
@property (readonly) CGDirectDisplayID displayID;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// DDC/CI over the Apple Silicon display coprocessor (same calls m1ddc and MonitorControl use).
typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef _Nullable IOAVServiceCreateWithService(CFAllocatorRef _Nullable allocator, io_service_t service) CF_RETURNS_RETAINED;
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

NS_ASSUME_NONNULL_END
