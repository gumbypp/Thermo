//
//  common.m
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

@implementation Logger

+ (Logger *)sharedLogger
{
    static dispatch_once_t pred;
    static Logger *shared = nil;
    
    dispatch_once(&pred, ^{
        shared = [[self alloc] init];
    });
    
    return shared;
}

+ (void)logLevel:(NSInteger)level loc:(const char *)loc msg:(NSString *)format, ...
{
    if (!(level & [Logger sharedLogger].loggingLevel)) {
        return;
    }
    
    va_list arguments;
	
	va_start(arguments, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);
    
    switch (level)
    {
        case kLogLevelDebug:
            NSLog(@"%s > %@", loc, message);
            break;
            
        case kLogLevelInfo:
            NSLog(@"%s %@", loc, message);
            break;
            
        case kLogLevelWarn:
            NSLog(@"%s [Warning] %@", loc, message);
            break;
            
        case kLogLevelError:
            NSLog(@"%s [Error] %@", loc, message);
            break;
    }
}

@end

@implementation Common

+ (NSString *)getSchedulePriorityForIndex:(int)index
{
    switch (index) {
        case 0:
            return @"HIGH";
            
        case 1:
            return @"MED";
            
        case 2:
            return @"LOW";
            
        default:
            break;
    }
    
    return @"ERROR";
}

@end
