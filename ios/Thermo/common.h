//
//  common.h
//  Thermo
//
//  Created by Dale Low on 5/30/14.
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

#import <UIKit/UIKit.h>

#import "shared_key.h"
#import "shared_protocol.h"

// logger
typedef NS_ENUM(NSInteger, LogLevel)
{
    kLogLevelDebug = (1 << 0),
    kLogLevelInfo  = (1 << 1),
    kLogLevelWarn  = (1 << 2),
    kLogLevelError = (1 << 3),
    kLogLevelAll   = kLogLevelDebug | kLogLevelInfo | kLogLevelWarn | kLogLevelError,
};

#define NSLogDebug(...)     [Logger logLevel:kLogLevelDebug loc:__PRETTY_FUNCTION__ msg:__VA_ARGS__]
#define NSLogInfo(...)      [Logger logLevel:kLogLevelInfo loc:__PRETTY_FUNCTION__ msg:__VA_ARGS__]
#define NSLogWarn(...)      [Logger logLevel:kLogLevelWarn loc:__PRETTY_FUNCTION__ msg:__VA_ARGS__]
#define NSLogError(...)     [Logger logLevel:kLogLevelError loc:__PRETTY_FUNCTION__ msg:__VA_ARGS__]

@interface Logger : NSObject

@property (nonatomic, assign) LogLevel loggingLevel;

+ (Logger *)sharedLogger;
+ (void)logLevel:(NSInteger)level loc:(const char *)loc msg:(NSString *)format, ...;

@end

@interface Common : NSObject

+ (NSString *)getSchedulePriorityForIndex:(int)index;

@end