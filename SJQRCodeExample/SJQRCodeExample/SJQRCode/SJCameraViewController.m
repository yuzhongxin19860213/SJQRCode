//
//  SJCameraViewController.m
// Copyright (c) 2011–2017 Alamofire Software Foundation
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "SJCameraViewController.h"

NSString *const SJCameraErrorDomain = @"com.SJQRCode.SJCameraErrorDomain";
NSString *const SJCameraErrorFailedToAddInput = @"SJThumbnailNotification";

@interface SJCameraViewController ()<AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureDevice *activeCamera;
@property (nonatomic, assign) AVCaptureDeviceInput *activeVideoInput;
@property (nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
@property (nonatomic, strong) dispatch_queue_t videoQueue;

@end

@implementation SJCameraViewController

#pragma mark - Propertys

- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer {
    if (!_captureVideoPreviewLayer) {
        _captureVideoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
        _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    }
    return _captureVideoPreviewLayer;
}

- (NSString *)sessionPreset{
    return AVCaptureSessionPresetHigh;
}

- (dispatch_queue_t)videoQueue {
    return dispatch_queue_create("com.SJQRCode.videoQueue", NULL);
}

#pragma mark - Public Event

- (void)showCaptureOnView:(UIView *)preview {
    NSError *error;
    if ([self setupSession:&error]) {
        [self startSession];
    } else {
        NSLog(@"Error:%@",[error localizedDescription]);
    }
    
    self.captureVideoPreviewLayer.frame = preview.bounds;
    [preview.layer addSublayer:self.captureVideoPreviewLayer];
}

- (void)startSession {
    if (![self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)stopSession {
    if ([self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession stopRunning];
        });
    }
}

- (BOOL)setupSession:(NSError **)error {
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = [self sessionPreset];
    if (![self setupSessionInputs:error]) {
        return NO;
    }
    if (![self setupSessionOutputs:error]) {
        return NO;
    }
    return YES;
}

//AVCaptureAutoFocusRangeRestrictionNear ios7版本新增的属性，允许我们使用一个范围的约束对这个功能进行定制，我们扫描的大部分条码距离都不远，所以可以通过缩小扫描区域来提升识别的成功率。检测是否支持该功能
- (BOOL)setupSessionInputs:(NSError *__autoreleasing *)error {
    BOOL success = [self setupFatherSessionInputs:error];
    if (success) {
        if (self.activeCamera.autoFocusRangeRestrictionSupported) {         // 3
            if ([self.activeCamera lockForConfiguration:error]) {
                self.activeCamera.autoFocusRangeRestriction =
                AVCaptureAutoFocusRangeRestrictionNear;
                [self.activeCamera unlockForConfiguration];
            }
        }
    }
    return success;
}

- (BOOL)setupSessionOutputs:(NSError **)error {
    self.metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if ([self.captureSession canAddOutput:self.metadataOutput]) {
        [self.captureSession addOutput:self.metadataOutput];
        dispatch_queue_t mainqueue = dispatch_get_main_queue();
        [self.metadataOutput setMetadataObjectsDelegate:self queue:mainqueue];
        //设置扫描的类型
        NSArray *typesArr = @[AVMetadataObjectTypeQRCode,AVMetadataObjectTypeAztecCode,AVMetadataObjectTypePDF417Code,AVMetadataObjectTypeInterleaved2of5Code,AVMetadataObjectTypeUPCECode,AVMetadataObjectTypeCode39Code,AVMetadataObjectTypeCode39Mod43Code,AVMetadataObjectTypeEAN13Code,AVMetadataObjectTypeEAN8Code,AVMetadataObjectTypeCode93Code,AVMetadataObjectTypeCode128Code];
        self.metadataOutput.metadataObjectTypes = typesArr;
        // self.rectrectOfInterest = CGRectMake(100, 100, 100, 100);
        //self.metadataOutput.rectOfInterest = [self.captureVideoPreviewLayer metadataOutputRectOfInterestForRect:self.rectrectOfInterest];
        NSLog(@"%@",NSStringFromCGRect(self.metadataOutput.rectOfInterest));
    } else {
        NSDictionary *usernfoDic = @{NSLocalizedDescriptionKey:@"Fail add metadata output"};
        *error = [NSError errorWithDomain:SJCameraErrorDomain code:SJCameraErrorCodeFailedToAddOutput userInfo:usernfoDic];
        return NO;
    }
    return YES;
}

- (BOOL)setupFatherSessionInputs:(NSError **)error {
    AVCaptureDevice *videoDevice =
    [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    self.activeCamera = videoDevice;
    AVCaptureDeviceInput *videoInput =
    [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:error];
    if (videoInput) {
        if ([self.captureSession canAddInput:videoInput]) {
            [self.captureSession addInput:videoInput];
            self.activeVideoInput = videoInput;
        } else {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Failed to add video input."};
            *error = [NSError errorWithDomain:SJCameraErrorDomain code:SJCameraErrorCodeFailedToAddInput userInfo:userInfo];
            return NO;
        }
    } else {
        return NO;
    }
    
    return YES;
}

#pragma mark - Configuration Flash

- (BOOL)cameraHasTorch {
    return [[self activeCamera] hasTorch];
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode{
    AVCaptureDevice *device = [self activeCamera];
    if (device.torchMode != torchMode && [device isTorchModeSupported:torchMode]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            device.torchMode = torchMode;
            [device unlockForConfiguration];
        } else {
            NSLog(@"%@",error);
        }
    }
}

#pragma mark - Read the photo album of QRCode  读取相册的中二维码

- (NSString *)readAlbumQRCodeImage:(UIImage *)imagePicker {
    CIImage *qrcodeImage = [CIImage imageWithCGImage:imagePicker.CGImage];
    CIContext *qrcodeContext = [CIContext contextWithOptions:nil];
    CIDetector *qrcodeDetector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:qrcodeContext options:@{CIDetectorAccuracy:CIDetectorAccuracyHigh}];
    NSArray *qrcodeFeaturesArr = [qrcodeDetector featuresInImage:qrcodeImage];
    NSString *qrCodeString = nil;
    if (qrcodeFeaturesArr && qrcodeFeaturesArr.count > 0) {
        for (CIQRCodeFeature *feature in qrcodeFeaturesArr) {
            if (qrCodeString && qrCodeString.length > 0) {
                break;
            }
            qrCodeString = feature.messageString;
        }
    }
    
    NSString *alertMessageString = nil;
    if (qrCodeString) {
        [self stopSession];
        alertMessageString = qrCodeString;
    } else {
        alertMessageString = @"照片中未检测到二维码";
    }
    return alertMessageString;
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate Delagate

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    [self stopSession];
    BOOL isAvailable = YES;
    if (metadataObjects.count > 0 && isAvailable == YES) {
        isAvailable = NO;
        NSString *metadataString = nil;
        AudioServicesPlaySystemSound(1360);
        AVMetadataMachineReadableCodeObject *MetadataObject = [metadataObjects objectAtIndex:0];
        metadataString = MetadataObject.stringValue;
        [self.delegate cameraControllerDidDetectCodes:metadataString];
    }
}


@end
