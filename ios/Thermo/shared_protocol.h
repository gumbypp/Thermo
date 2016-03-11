//
//  shared_protocol.h
//  Thermo
//
//  Created by Dale Low on 1/17/16.
//  Copyright (c) 2016 gumbypp consulting. All rights reserved.
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

#ifndef Thermo_shared_protocol_h
#define Thermo_shared_protocol_h

// protocol
#define kHeaderLen                    4

#define kCmdGetKeyPart                1
#define kCmdGetTemps                  2
#define kCmdSetDateTime               3
#define kCmdSetTargetTemp             4
#define kCmdGetWeekdayTempSchedule    5
#define kCmdGetWeekendTempSchedule    6
#define kCmdSetWeekdayTempSchedule    7
#define kCmdSetWeekendTempSchedule    8

#define kResponseSignature            0xA0
#define kResponseOK                   0x00
#define kResponseErrorSig             0x01
#define kResponseErrorInvalidCommand  0x02
#define kResponseErrorInvalidLength   0x03

// misc
#define kMinTargetTempF               32
#define kMaxTargetTempF               99
#define kSignatureLength              8
#define kSecondsPerMinute             60
#define kMinutesPerHour               60
#define kSecondsPerHour               (kSecondsPerMinute*kMinutesPerHour)
#define kHoursPerDay                  24
#define kSecondsPerDay                (kSecondsPerHour*kHoursPerDay)
#define kScheduleOptionCount          3

#endif
