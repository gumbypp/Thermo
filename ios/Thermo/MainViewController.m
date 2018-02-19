//
//  MainViewController.m
//  Thermo
//
//  Created by Dale Low on 4/28/14.
//  Copyright (c) 2014 gumbypp consulting. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// - The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "BLE.h"
#import "MD5/MD5.h"
#import "ScheduleViewController.h"

#import "MainViewController.h"

typedef NS_ENUM(NSInteger, BLEState)
{
    kBLEStateIdle,
    kBLEStateScanning,
    kBLEStateConnecting,
    kBLEStateConnected
};

typedef NS_ENUM(NSInteger, ConnectButtonState) {
    kConnectButtonStateConnect,
    kConnectButtonStateAbort,
    kConnectButtonStateDisconnect
};

typedef NS_ENUM(NSInteger, RequestState) {
    kRequestStateIdle,
    kRequestStateSending
};

union hex {
    uint16_t unsign;
    int16_t sign;
    struct {
        uint8_t low;
        uint8_t high;
    } byte;
};

union long_hex {
    uint32_t lunsign;
    struct {
        uint8_t b0;
        uint8_t b1;
        uint8_t b2;
        uint8_t b3;
    } lbytes;
};

typedef void (^CompletionHandler)(NSData *responseData, NSError *error);

// misc
#define kTargetTitle                @"TARGET"
#define kHumidityTitle              @"HUMIDITY"

// comms
#define kScanTimeout                15
#define kConnectTimeout             5
#define kPollInterval               30
#define kMaxRetryCount              2

// transport
#define kErrorDomain                @"ViewController"
#define kErrorCodeSendFailed        -1
#define kErrorCodeDisconnect        -2
#define kErrorCodeResponseInvalid   -3  // unexpected first response byte
#define kErrorCodeResponseTooShort  -4  // response was too short
#define kErrorCodeSequenceMismatch  -5  // response sequence code did not match request
#define kErrorCodeAuthFailed        -6  // device auth failed
#define kErrorCodeLengthMismatch    -7  // response length didn't match reported value
#define kErrorCodeInvalidLength     -8  // device got wrong request length

///////////////////////////////////////////////////////////////////////////////

@interface Transaction : NSObject

@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) uint8_t messageSequenceNumber;
@property (nonatomic, copy) CompletionHandler completionHandler;

@end

@implementation Transaction

- (id)initWithData:(NSData *)data messageSequenceNumber:(uint8_t)messageSequenceNumber completionHandler:(CompletionHandler)completionHandler
{
    self = [super init];
    if (self) {
        _data = data;
        _messageSequenceNumber = messageSequenceNumber;
        _completionHandler = completionHandler;
    }
    return self;
}

@end

///////////////////////////////////////////////////////////////////////////////

@interface MainViewController () <BLEDelegate, ScheduleViewControllerDelegate>

@property (nonatomic, weak) IBOutlet UILabel *titleLabel;
@property (nonatomic, weak) IBOutlet UIView *connectView;
@property (nonatomic, weak) IBOutlet UIButton *btnConnect;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView *indConnecting;
@property (nonatomic, weak) IBOutlet UIButton *btnDisconnect;
@property (nonatomic, weak) IBOutlet UILabel *currentTempLabel;
@property (nonatomic, weak) IBOutlet UILabel *humidityLabel;
@property (nonatomic, weak) IBOutlet UILabel *targetTempLabel;
@property (nonatomic, weak) IBOutlet UIButton *scheduleButton;
@property (nonatomic, weak) IBOutlet UILabel *infoLabel;
@property (nonatomic, weak) IBOutlet UIView *knobContainer;

@property (nonatomic, assign) BLEState bleState;
@property (nonatomic, strong) BLE *ble;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) uint8_t sequenceNumber;
@property (nonatomic, assign) uint8_t activeSequenceNumber;
@property (nonatomic, assign) uint32_t keyPart;
@property (nonatomic, retain) NSMutableArray *transactionQueue;
@property (nonatomic, assign) RequestState requestState;
@property (nonatomic, strong) NSData *retryPayload;
@property (nonatomic, assign) int retryCount;
@property (nonatomic, copy) CompletionHandler completionHandler;
@property (nonatomic, assign) int currentTemp;
@property (nonatomic, assign) int targetTemp;
@property (nonatomic, assign) float newTargetTempDelta;
@property (nonatomic, strong) UIImageView *knobView;
@property (nonatomic, assign) CGPoint panStartingPoint;
@property (nonatomic, assign) BOOL panIgnoreRemaining;
@property (nonatomic, assign) CGFloat lastKnobRotation;
@property (nonatomic, assign) CGRect lastKnobContainerBounds;

@end

///////////////////////////////////////////////////////////////////////////////

@implementation MainViewController

- (id)init
{
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    _bleState = kBLEStateIdle;
    _transactionQueue = [[NSMutableArray alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.requestState = kRequestStateIdle;
    
    self.ble = [[BLE alloc] init];
    [_ble controlSetup];
    _ble.delegate = self;
    
    [self configureUXWithConnectButtonState:kConnectButtonStateConnect];
    [self resetLabels];
    
    UIPanGestureRecognizer *pgr = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(knobDragging:)];
    [self.knobContainer addGestureRecognizer:pgr];
    self.knobContainer.userInteractionEnabled = NO;
    
    // put knob in default position
    [self.knobView removeFromSuperview];
    self.knobView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"dial"]];
    [self.knobContainer addSubview:self.knobView];
    self.lastKnobRotation = 0;
    
    // use "small caps" for the title
    UIFont *systemFont = [UIFont systemFontOfSize:24 weight:UIFontWeightLight];
    UIFontDescriptor *smallCapsDesc = [systemFont.fontDescriptor fontDescriptorByAddingAttributes:@{ UIFontDescriptorFeatureSettingsAttribute : @[@{
                                                                                                             UIFontFeatureTypeIdentifierKey: @(37),         // kLowerCaseType
                                                                                                             UIFontFeatureSelectorIdentifierKey: @(1)}]}];   // kLowerCaseSmallCapsSelector
    self.titleLabel.font = [UIFont fontWithDescriptor:smallCapsDesc size:24];
    self.titleLabel.text = @"Thermo";
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    // this gets called multiple times - so the only thing that we can do is continue
    // if the frame of thing that we're relying on has changed
    if (CGRectEqualToRect(self.lastKnobContainerBounds, self.knobContainer.bounds)) {
        return;
    }
    
    self.lastKnobContainerBounds = self.knobView.frame = self.knobContainer.bounds;
}

#pragma mark - Internal methods

- (NSData *)bigEndianDataForDword:(uint32_t)value
{
    union long_hex lu;
    uint8_t a[4];
    
    lu.lunsign = value;
    a[0] = lu.lbytes.b3;
    a[1] = lu.lbytes.b2;
    a[2] = lu.lbytes.b1;
    a[3] = lu.lbytes.b0;
    
    return [NSData dataWithBytes:a length:4];
}

- (uint32_t)dwordForBigEndianData:(NSData *)value
{
    union long_hex lu;
    uint8_t *bytes = (uint8_t *)[value bytes];
    
    lu.lbytes.b3 = *bytes++;
    lu.lbytes.b2 = *bytes++;
    lu.lbytes.b1 = *bytes++;
    lu.lbytes.b0 = *bytes++;
    
    return lu.lunsign;
}

- (NSData *)getSignatureForBytes:(uint8_t *)bytes length:(NSUInteger)length key1:(uint32_t)key1 key2:(uint32_t)key2
{
    NSMutableData *data = [[NSMutableData alloc] initWithBytes:bytes length:length];
    
    [data appendData:[self bigEndianDataForDword:key1]];
    [data appendData:[self bigEndianDataForDword:key2]];
    
    // create a half-length signature by XORing the two parts together
    // note: make_hash returns pointer to global data - not thread-safe
    uint8_t *fullSignature = make_hash((unsigned char*)[data bytes], [data length]);
    
    uint8_t result[kSignatureLength];
    memcpy(result, fullSignature, kSignatureLength);
    for (int i=0; i<kSignatureLength; i++) {
        result[i] ^= fullSignature[kSignatureLength + i];
    }

    return [NSData dataWithBytes:result length:kSignatureLength];
}

- (void)configureUXWithConnectButtonState:(ConnectButtonState)state
{
    BOOL connected = NO;
    BOOL showProgress = NO;
    switch (state) {
        case kConnectButtonStateConnect:
            [self.btnConnect setImage:[UIImage imageNamed:@"ble_start"] forState:UIControlStateNormal];
            break;

        case kConnectButtonStateAbort:
            [self.btnConnect setImage:[UIImage imageNamed:@"ble_cancel"] forState:UIControlStateNormal];
            showProgress = YES;
            break;

        case kConnectButtonStateDisconnect:
            connected = YES;
            break;
    }

    self.connectView.hidden = connected;
    self.currentTempLabel.hidden = !connected;
    self.knobContainer.userInteractionEnabled = connected;
    self.btnDisconnect.hidden = self.scheduleButton.hidden = !connected;
    
    if (showProgress) {
        self.indConnecting.hidden = NO;
        [self.indConnecting startAnimating];
    } else {
        [self.indConnecting stopAnimating];
        self.indConnecting.hidden = YES;
    }
}

- (void)connectOrDisconnect
{
    switch (self.bleState) {
        case kBLEStateIdle:
            if (self.ble.peripherals) {
                self.ble.peripherals = nil;
            }
            
            // BLE mini
            [self.ble findBLEPeripheralsWithName:@"Biscuit"];
            
            self.timer = [NSTimer scheduledTimerWithTimeInterval:kScanTimeout target:self selector:@selector(timeout:) userInfo:nil repeats:NO];
            [self configureUXWithConnectButtonState:kConnectButtonStateAbort];
            self.bleState = kBLEStateScanning;
            break;
            
        case kBLEStateScanning:
        case kBLEStateConnecting:
            if (kBLEStateScanning == self.bleState) {
                [self.ble stopFindingPeripherals];
            } else {
                NSAssert(self.ble.connectingPeripheral, @"connectOrDisconnect - must have connectingPeripheral");
                [self.ble disconnectPeripheral:self.ble.connectingPeripheral];
            }
            
            [self configureUXWithConnectButtonState:kConnectButtonStateConnect];
            self.bleState = kBLEStateIdle;
            break;
            
        case kBLEStateConnected:
            NSAssert(self.ble.activePeripheral, @"must have activePeripheral");
            if (self.ble.activePeripheral.state == CBPeripheralStateConnected) {
                [self.ble disconnectPeripheral:self.ble.activePeripheral];
            } else {
                self.bleState = kBLEStateIdle;
            }
            break;
    }
}

- (void)queueOrSendMessageWithCommand:(uint8_t)cmd
                              payload:(NSData *)payload
                  withCompletionBlock:(CompletionHandler)completionBlock
{
    uint8_t buf[3];
    buf[0] = cmd;
    buf[1] = ++self.sequenceNumber;
    buf[2] = [payload length];
    
    NSMutableData *fullPayload = [[NSMutableData alloc] initWithBytes:buf length:sizeof(buf)];
    if (payload) {
        [fullPayload appendData:payload];
    }
    
    // data = signature + fullPayload
    NSMutableData *data = [[self getSignatureForBytes:(uint8_t *)[fullPayload bytes]
                                               length:[fullPayload length]
                                                 key1:kSharedKey
                                                 key2:self.keyPart] mutableCopy];
    [data appendData:fullPayload];
    
    if (kRequestStateIdle == self.requestState) {
        NSLogDebug(@"sending request immediately: %@", data);
        [self sendMessageWithPayload:data messageSequenceNumber:self.sequenceNumber retryCount:0 withCompletionBlock:completionBlock];
    } else {
        NSLogDebug(@"queuing request: %@", data);
        [self.transactionQueue addObject:[[Transaction alloc] initWithData:data
                                                     messageSequenceNumber:self.sequenceNumber
                                                         completionHandler:completionBlock]];
    }
}

- (void)sendMessageWithPayload:(NSData *)payload
         messageSequenceNumber:(uint8_t)messageSequenceNumber
                    retryCount:(int)retryCount
           withCompletionBlock:(CompletionHandler)completionBlock
{
    NSAssert(kRequestStateIdle == self.requestState, @"assert: expect kRequestStateIdle");
    
    if (![self.ble write:payload]) {
        NSLogWarn(@"failed to send: %@", payload);
        completionBlock(nil, [NSError errorWithDomain:kErrorDomain code:kErrorCodeSendFailed userInfo:nil]);
    } else {
        NSLogDebug(@"message %@ sent - waiting for response", payload);
        
        self.activeSequenceNumber = messageSequenceNumber;
        self.requestState = kRequestStateSending;
        if (!retryCount) {
            // save in case we need to do a retry later
            self.retryPayload = payload;
        }
        self.retryCount = retryCount;
        self.completionHandler = completionBlock;
    }
}

- (void)invokeCompletionHandlerWithData:(NSData *)data error:(NSError *)error
{
    self.requestState = kRequestStateIdle;
    
    if (!self.completionHandler) {
        NSAssert(NO, @"assert: must have completion handler");
        return;
    }

    // the BLE mini seems to drop incoming chars sometime (kErrorCodeInvalidLength), so let's retry instead of giving up
    if ([error.domain isEqualToString:kErrorDomain] && (kErrorCodeInvalidLength == error.code) && (self.retryCount < kMaxRetryCount)) {
        NSLogWarn(@"doing retry, count=%d", self.retryCount);
        [self sendMessageWithPayload:self.retryPayload
               messageSequenceNumber:self.activeSequenceNumber
                          retryCount:++self.retryCount
                 withCompletionBlock:self.completionHandler];
        
        return;
    }
    
#ifdef DEBUG
//    if (self.retryCount) {
//        [[[UIAlertView alloc] initWithTitle:nil message:[NSString stringWithFormat:@"completed after %d retry(s)", self.retryCount]
//                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
//    }
#endif
    
    // make local copy to handle the case where sendMessageWithPayload is invoked before the completion handler returns
    CompletionHandler ch = self.completionHandler;
    ch(data, error);
    
    if (kRequestStateIdle != self.requestState) {
        NSLogDebug(@"completion handler started a new transaction - skipping check for pending transactions");
        return;
    }
    
    // check for a pending transaction
    if ([self.transactionQueue count]) {
        Transaction *nextTransaction = [self.transactionQueue objectAtIndex:0];
        [self.transactionQueue removeObjectAtIndex:0];
        
        NSLogDebug(@"starting next transaction");
        [self sendMessageWithPayload:nextTransaction.data
               messageSequenceNumber:nextTransaction.messageSequenceNumber
                          retryCount:0
                 withCompletionBlock:nextTransaction.completionHandler];
    }
}

- (void)timeout:(NSTimer *)timer
{
    if (timer && (timer != self.timer)) {
        return;
    }
    
    switch (self.bleState) {
        case kBLEStateIdle:
            break;
            
        case kBLEStateScanning:
        case kBLEStateConnecting:
            // failed...
            NSLogWarn(@"failed during state %d", self.bleState);
            if (kBLEStateScanning == self.bleState) {
                [self.ble stopFindingPeripherals];
            } else {
                NSAssert(self.ble.connectingPeripheral, @"timeout - must have connectingPeripheral");
                [self.ble disconnectPeripheral:self.ble.connectingPeripheral];
            }
            
            self.timer = nil;
            [self configureUXWithConnectButtonState:kConnectButtonStateConnect];
            self.bleState = kBLEStateIdle;
            break;
            
        case kBLEStateConnected:
            [self queueOrSendMessageWithCommand:kCmdGetTemps payload:nil withCompletionBlock:^(NSData *responseData, NSError *error) {
                if (error) {
                    NSLogWarn(@"kCmdGetTemps failed: %@", error.localizedDescription);
                } else {
                    NSLogDebug(@"kCmdGetTemps response: %@", responseData);
                    if ([responseData length] == 7) {
                        uint8_t *p = (uint8_t *)[responseData bytes];
                        
                        BOOL heatOn = *p++;
                        
                        union hex u;
                    
                        u.byte.high = *p++;
                        u.byte.low = *p++;
                        self.currentTemp = u.unsign;

                        int humidity = (int)*p++;
                        
                        u.byte.high = *p++;
                        u.byte.low = *p++;
                        int lastTargetTemp = self.targetTemp;
                        self.targetTemp = u.unsign;
                        
                        // compensate for non-zero delta when this update came in
                        if (lastTargetTemp && self.newTargetTempDelta) {
                            self.newTargetTempDelta += lastTargetTemp - self.targetTemp;
                        } else {
                            self.newTargetTempDelta = 0;
                        }
                        
                        int activeSchedule = (int)*p++;
                        
                        self.currentTempLabel.text = [NSString stringWithFormat:@"%d°F", self.currentTemp];
                        [self updateHumidityLabel:humidity];
                        [self updateTargetTempLabel:(self.targetTemp + self.newTargetTempDelta)];
                        
                        self.infoLabel.text = [NSString stringWithFormat:@"Schedule: %@\nHeat: %@",
                                               activeSchedule ? [Common getSchedulePriorityForIndex:(activeSchedule - 1)] : @"MANUAL",
                                               heatOn ? @"ON" : @"OFF"];
                    }
                }
            }];
            break;
    }
}

- (void)showErrorMessage:(NSString *)commandName error:(NSError *)error
{
    NSLogWarn(@"%@: command failed with error: %@", commandName, error.localizedDescription);
    
    [[[UIAlertView alloc] initWithTitle:@"Communications error"
                                message:[NSString stringWithFormat:@"%@ command failed\n%@", commandName, error.localizedDescription]
                               delegate:nil
                      cancelButtonTitle:@"OK"
                      otherButtonTitles:nil] show];
}

- (void)getKeyPartWithCompletionBlock:(CompletionHandler)completionBlock
{
    [self queueOrSendMessageWithCommand:kCmdGetKeyPart payload:nil withCompletionBlock:^(NSData *responseData, NSError *error) {
        if (error) {
            [self showErrorMessage:@"GetKeyPart" error:error];
            completionBlock(nil, error);
            return;
        }
        
        NSLogDebug(@"kCmdGetKeyPart response: %@", responseData);
        if ([responseData length] == 4) {
            self.keyPart = [self dwordForBigEndianData:responseData];
            NSLogDebug(@"keyPart: %08x", self.keyPart);
            
            completionBlock(nil, nil);
        } else {
            completionBlock(nil, [NSError errorWithDomain:kErrorDomain code:kErrorCodeAuthFailed userInfo:nil]);
        }
    }];
}

- (void)sendTargetTempDelta
{
    if ((kBLEStateConnected != self.bleState) || !self.targetTemp) {
        NSLogWarn(@"cannot modify target temp in state %d", self.bleState);
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    [self getKeyPartWithCompletionBlock:^(NSData *notUsed, NSError *error) {
        if (error) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.newTargetTempDelta = 0;
            [self updateTargetTempLabel:self.targetTemp];
        } else {
            int newTargetTemp = self.targetTemp + round(self.newTargetTempDelta);
            
            uint8_t buf[1];
            buf[0] = newTargetTemp;
            NSData *data = [[NSData alloc] initWithBytes:buf length:sizeof(buf)];
            
            NSLogDebug(@"kCmdSetTargetTemp request: %@", data);
            [self queueOrSendMessageWithCommand:kCmdSetTargetTemp payload:data withCompletionBlock:^(NSData *responseData, NSError *error) {
                [MBProgressHUD hideHUDForView:self.view animated:YES];
                
                self.newTargetTempDelta = 0;
                if (error) {
                    [self showErrorMessage:@"SetTargetTemp" error:error];
                    [self updateTargetTempLabel:self.targetTemp];
                } else {
                    NSLogDebug(@"kCmdSetTargetTemp response: %@", responseData);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self timeout:nil]; // force update after giving thermostat a chance to update its internal state
                    });
                }
            }];
        }
    }];
}

- (void)sendCurrentDateTime
{
    if (kBLEStateConnected != self.bleState) {
        NSLogWarn(@"cannot modify date/time in state %d", self.bleState);
        return;
    }

    [self getKeyPartWithCompletionBlock:^(NSData *notUsed, NSError *error) {
        if (!error) {
            uint8_t buf[6];
            uint8_t *p = buf;
            union hex u;
            
            NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute
                                                                           fromDate:[NSDate date]];
            
            u.unsign = [components year];
            *p++ = u.byte.high;     // year (ex: 2016)
            *p++ = u.byte.low;
            *p++ = [components month];
            *p++ = [components day];
            *p++ = [components hour];
            *p++ = [components minute];
            
            NSData *data = [[NSData alloc] initWithBytes:buf length:sizeof(buf)];
            
            NSLogDebug(@"kCmdSetDateTime request: %@", data);
            [self queueOrSendMessageWithCommand:kCmdSetDateTime payload:data withCompletionBlock:^(NSData *responseData, NSError *error) {
                if (error) {
                    [self showErrorMessage:@"SetDateTime" error:error];
                } else {
                    NSLogDebug(@"kCmdSetDateTime response: %@", responseData);
                }
            }];
        }
    }];
}

- (CGPoint)convertFromUIKitULOCoordinate:(CGPoint)point viewSize:(CGSize)viewSize
{
    return CGPointMake(point.x - viewSize.width/2, viewSize.height/2 - point.y);
}

- (void)resetLabels
{
    self.currentTempLabel.text = @"--";
    self.humidityLabel.text = nil;
    self.targetTempLabel.text = nil;
    self.infoLabel.text = nil;
}

- (void)updateHumidityLabel:(int)humidity
{
    NSString *humidityString = [NSString stringWithFormat:@"%@\n%d %%", kHumidityTitle, humidity];
    NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:humidityString];
    [attrString addAttribute:NSFontAttributeName
                       value:[UIFont systemFontOfSize:36.0]
                       range:NSMakeRange(0, humidityString.length)];
    [attrString addAttribute:NSFontAttributeName
                       value:[UIFont systemFontOfSize:16.0]
                       range:NSMakeRange(0, kHumidityTitle.length)];
    
    self.humidityLabel.attributedText = attrString;
}

- (void)updateTargetTempLabel:(int)targetTemp
{
    NSString *targetString = [NSString stringWithFormat:@"%@\n%d°F", kTargetTitle, targetTemp];
    NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithString:targetString];
    [attrString addAttribute:NSFontAttributeName
                       value:[UIFont systemFontOfSize:36.0]
                       range:NSMakeRange(0, targetString.length)];
    [attrString addAttribute:NSFontAttributeName
                       value:[UIFont systemFontOfSize:16.0]
                       range:NSMakeRange(0, kTargetTitle.length)];
    
    self.targetTempLabel.attributedText = attrString;
}

#pragma mark - Event handlers

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // dismiss schedule screen if active
    [self dismissViewControllerAnimated:NO completion:nil];
    
    if (kBLEStateIdle != self.bleState) {
        [self connectOrDisconnect];
    }
}

- (IBAction)connectPressed:(id)sender
{
    NSLogDebug(@"entered");
    
    [self connectOrDisconnect];
}

- (IBAction)disconnectPressed:(id)sender
{
    NSLogDebug(@"entered");
    
    [self connectOrDisconnect];
}

- (IBAction)schedulePressed:(id)sender
{
    if (kBLEStateConnected != self.bleState) {
        NSLogWarn(@"cannot get schedule in state %d", self.bleState);
        return;
    }

    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    [self queueOrSendMessageWithCommand:kCmdGetWeekdayTempSchedule payload:nil withCompletionBlock:^(NSData *weekdaySchedule, NSError *error) {
        if (error) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [self showErrorMessage:@"GetWeekdayTempSchedule" error:error];
        } else {
            NSLogDebug(@"kCmdGetWeekdayTempSchedule response: %@", weekdaySchedule);
            [self queueOrSendMessageWithCommand:kCmdGetWeekendTempSchedule payload:nil withCompletionBlock:^(NSData *weekendSchedule, NSError *error) {
                [MBProgressHUD hideHUDForView:self.view animated:YES];
                if (error) {
                    [self showErrorMessage:@"GetWeekendTempSchedule" error:error];
                } else {
                    NSLogDebug(@"kCmdGetWeekendTempSchedule response: %@", weekendSchedule);
                    
                    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:[NSBundle mainBundle]];
                    
                    ScheduleViewController *vc = [storyboard instantiateViewControllerWithIdentifier:@"ScheduleViewController"];
                    vc.delegate = self;
                    vc.rawWeekdaySchedule = weekdaySchedule;
                    vc.rawWeekendSchedule = weekendSchedule;
                    [self presentViewController:vc animated:YES completion:nil];
                }
            }];
        }
    }];
}

- (void)knobDragging:(UIPanGestureRecognizer *)gesture
{
    CGSize containerSize = gesture.view.frame.size;
    
    // first touch?
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.panStartingPoint = [self convertFromUIKitULOCoordinate:[gesture locationInView:gesture.view] viewSize:containerSize];
        self.panIgnoreRemaining = NO;
        return;
    }
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self sendTargetTempDelta];
        return;
    }
    
    if (self.panIgnoreRemaining) {
        return;
    }

    // out of bounds?
    CGPoint newPoint = [self convertFromUIKitULOCoordinate:[gesture locationInView:gesture.view] viewSize:containerSize];
    if ((newPoint.x < -containerSize.width/2) || (newPoint.x > containerSize.width/2) ||
        (newPoint.y < -containerSize.height/2) || (newPoint.y > containerSize.height/2)) {
        self.panIgnoreRemaining = YES;
        return;
    }
    
    CGFloat x1 = self.panStartingPoint.x;
    CGFloat y1 = self.panStartingPoint.y;
    CGFloat x2 = newPoint.x;
    CGFloat y2 = newPoint.y;
    
    CGFloat dX = x2 - x1;
    CGFloat dY = y2 - y1;
    CGFloat hypotenuse = sqrtf(dX*dX + dY*dY);
    
    CGFloat theta1 = atan2f(y1, x1);
    CGFloat alpha = atan2f(y2 - y1, x2 - x1);
    CGFloat beta = M_PI/2 - theta1 + alpha;
    CGFloat movePoints = hypotenuse * cosf(beta);
    
    // this adjustment seems about right to convert points to radians
    self.lastKnobRotation += movePoints/110;
    CGAffineTransform newTransform = CGAffineTransformMakeRotation(self.lastKnobRotation);
    [self.knobView setTransform:newTransform];
    
    //    NSLogDebug(@"x1=%.1f, y1=%.1f --> x2=%.1f, y2=%.1f (dX=%.1f, dY=%.1f)", x1, y1, x2, y2, dX, dY);
    //    NSLogDebug(@"theta1=%.1f, alpha=%.1f, beta=%.1f", theta1*360/2/M_PI, alpha*360/2/M_PI, beta*360/2/M_PI);
    //    NSLogDebug(@"hypotenuse = %.1f, beta = %.1f degrees, movePoints = %.1f", hypotenuse, beta*360/2/M_PI, movePoints);
    NSLogDebug(@"adjustment %.3f/N --> %.3f radians", movePoints, self.lastKnobRotation);
    
    if (kBLEStateConnected == self.bleState) {
        // update display while user is rotating the dial
        self.newTargetTempDelta += (float)movePoints/20;
        
        int newDisplayTargetTemp = self.targetTemp + round(self.newTargetTempDelta);
        if (newDisplayTargetTemp > kMaxTargetTempF) {
            newDisplayTargetTemp = kMaxTargetTempF;
            self.newTargetTempDelta = kMaxTargetTempF - self.targetTemp;
        } else if (newDisplayTargetTemp < kMinTargetTempF) {
            newDisplayTargetTemp = kMinTargetTempF;
            self.newTargetTempDelta = kMinTargetTempF - self.targetTemp;
        }
        
        [self updateTargetTempLabel:newDisplayTargetTemp];
    }
    
    self.panStartingPoint = newPoint;
}

#pragma mark - BLEDelegate methods

- (void)ble:(BLE *)ble didDiscoverPeripheral:(CBPeripheral *)peripheral
{
    [self.ble stopFindingPeripherals];
    
    NSLogDebug(@"connecting to first peripheral");
    [self.ble connectPeripheral:peripheral];
    
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:kConnectTimeout target:self selector:@selector(timeout:) userInfo:nil repeats:NO];
    [self configureUXWithConnectButtonState:kConnectButtonStateAbort];
    self.bleState = kBLEStateConnecting;
}

- (void)ble:(BLE *)ble didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLogDebug(@"entered");
    
    [self.timer invalidate];
    [self configureUXWithConnectButtonState:kConnectButtonStateDisconnect];

    self.bleState = kBLEStateConnected;

    [self sendCurrentDateTime];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval target:self selector:@selector(timeout:) userInfo:nil repeats:YES];
    [self timeout:nil]; // force initial update now
}

- (void)ble:(BLE *)ble didDisconnectPeripheral:(CBPeripheral *)peripheral
{
    NSLogDebug(@"entered");
    
    if (kRequestStateIdle != self.requestState) {
        [self invokeCompletionHandlerWithData:nil error:[NSError errorWithDomain:kErrorDomain code:kErrorCodeDisconnect userInfo:nil]];
    }
    
    [self.timer invalidate];
    self.timer = nil;
    [self configureUXWithConnectButtonState:kConnectButtonStateConnect];

    [self resetLabels];

    self.bleState = kBLEStateIdle;
}

- (void)ble:(BLE *)ble peripheral:(CBPeripheral *)peripheral didUpdateRSSI:(NSNumber *)rssi
{
}

- (void)ble:(BLE *)ble peripheral:(CBPeripheral *)peripheral didReceiveData:(unsigned char *)data length:(int)length
{
    NSMutableString *result = [NSMutableString stringWithCapacity:length*3];
    
    for (int i=0; i<length; i++) {
        [result appendFormat:@"%02X ", data[i]];
    }
    
    NSLogDebug(@"received <--- %@", result);
    
    if (kRequestStateIdle != self.requestState) {
        if (length < kHeaderLen) {
            [self invokeCompletionHandlerWithData:nil error:[NSError errorWithDomain:kErrorDomain code:kErrorCodeResponseTooShort userInfo:nil]];
        } else if (data[0] != kResponseSignature) {
            [self invokeCompletionHandlerWithData:nil error:[NSError errorWithDomain:kErrorDomain code:kErrorCodeResponseInvalid userInfo:nil]];
        } else if (data[2] == kResponseErrorInvalidLength) {
            // device length check error can be reported before it gets the sequence number, so we check this first
            if (length > 4) {
                NSLogWarn(@"device only got %d bytes for this request", data[4]);
            }
            [self invokeCompletionHandlerWithData:nil error:[NSError errorWithDomain:kErrorDomain code:kErrorCodeInvalidLength userInfo:nil]];
        } else if (data[1] != self.activeSequenceNumber) {
            NSLogWarn(@"got sequence number 0x%02x vs expected 0x%02x", data[1], self.activeSequenceNumber);
            [self invokeCompletionHandlerWithData:nil error:[NSError errorWithDomain:kErrorDomain code:kErrorCodeSequenceMismatch userInfo:nil]];
        } else if (data[2] == kResponseErrorSig) {
            [self invokeCompletionHandlerWithData:nil error:[NSError errorWithDomain:kErrorDomain code:kErrorCodeAuthFailed userInfo:nil]];
        } else if (data[3] != (length - kHeaderLen)) {
            [self invokeCompletionHandlerWithData:nil error:[NSError errorWithDomain:kErrorDomain code:kErrorCodeLengthMismatch userInfo:nil]];
        } else {
            NSMutableData *responseData = [[NSMutableData alloc] initWithBytes:data length:length];
            [responseData replaceBytesInRange:NSMakeRange(0, kHeaderLen) withBytes:NULL length:0];
            [self invokeCompletionHandlerWithData:responseData error:nil];
        }
    }
}

#pragma mark - ScheduleViewControllerDelegate methods

- (void)scheduleViewControllerDidCancel:(ScheduleViewController *)svc
{
}

- (void)scheduleViewController:(ScheduleViewController *)svc didEditWeekdaySchedule:(NSData *)weekdaySchedule
               weekendSchedule:(NSData *)weekendSchedule
{
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    [self getKeyPartWithCompletionBlock:^(NSData *notUsed, NSError *error) {
        if (error) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        } else {
            [self queueOrSendMessageWithCommand:kCmdSetWeekdayTempSchedule payload:weekdaySchedule withCompletionBlock:^(NSData *responseData, NSError *error) {
                if (error) {
                    [MBProgressHUD hideHUDForView:self.view animated:YES];
                    [self showErrorMessage:@"SetWeekdayTempSchedule" error:error];
                } else {
                    [self getKeyPartWithCompletionBlock:^(NSData *notUsed, NSError *error) {
                        if (error) {
                            [MBProgressHUD hideHUDForView:self.view animated:YES];
                        } else {
                            [self queueOrSendMessageWithCommand:kCmdSetWeekendTempSchedule payload:weekendSchedule withCompletionBlock:^(NSData *responseData, NSError *error) {
                                [MBProgressHUD hideHUDForView:self.view animated:YES];
                                if (error) {
                                    [self showErrorMessage:@"SetWeekendTempSchedule" error:error];
                                } else {
                                    [[[UIAlertView alloc] initWithTitle:nil
                                                                message:@"Schedule updated"
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil] show];
                                }
                            }];
                        }
                    }];
                }
            }];
        }
    }];
}

@end
