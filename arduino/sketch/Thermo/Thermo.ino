//
// Thermo - based on RBL SimpleControls app
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

//"services.h/spi.h/boards.h" is needed in every new project
#include <SPI.h>
#include <boards.h>
#include <DHT.h>
#include <EEPROM.h>
#include <MD5.h>
#include <Wire.h>
#include <RTClib.h>
#include <TimerOne.h>
#include <LiquidCrystal.h>
#include "shared_key.h"
#include "shared_protocol.h"

#define USE_BLE_MINI

#ifdef USE_BLE_MINI
  #include <ble_mini.h>

  #define ble_available BLEMini_available
  #define ble_read BLEMini_read
  #define ble_write BLEMini_write

  #define log(...)
  #define logWarn(...)
#else
  #define log Serial.print
  #define logWarn Serial.print("WARN: "); Serial.print
#endif

#define MIN(a,b) (((a)<(b))?(a):(b))
#define MAX(a,b) (((a)>(b))?(a):(b))

// application
#define kEEPROMSize                 64
#define kEEPROMSignatureLen         16
#define kLCDBlankLine               "                "
#define kDHTPin                     8
#define kHeatOnPin                  10
#define kButtonUpPin                6
#define kButtonDownPin              7
#define kRTC5vPin                   17    // pin 17 (analog pin 3) will be used to provide +5v to the RTC 
#define kRTCgndPin                  16    // pin 16 (analog pin 2) will be used to provide GND to the RTC
#define kTempArrayCount             5
#define kRequestMessageBaseLen      3     // cmd, seq, data len
#define kRequestMessageMaxDataLen   (20 - kSignatureLength - kRequestMessageBaseLen)  // BLE mini max char write is 20 bytes

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

typedef enum {
  kSunday = 0,
  kMonday,
  kTuesday,
  kWednesday,
  kThursday,
  kFriday,
  kSaturday
};
  

typedef struct {
  uint8_t startTimeQuarterHours[kScheduleOptionCount];   // 0=midnight, 1=12:15, etc
  uint8_t durationQuarterMinutes[kScheduleOptionCount];  // 1=15min, 2=30min, etc
  uint8_t targetTemp[kScheduleOptionCount];              /// deg F
} Schedule;
   
typedef union {
  struct {
    uint8_t data[kEEPROMSize];
    uint8_t checksum[kEEPROMSignatureLen];
  };
  struct {
    uint8_t targetTemp;
    Schedule weekdaySchedule;
    Schedule weekendSchedule;
    // the above should be less than kEEPROMSize
  };
} NVRam;
   
// globals
static union long_hex gKeyPart;
static DHT gDht(kDHTPin, DHT22);
static RTC_DS1307 gRtc;
static LiquidCrystal gLcd(12, 11, 5, 4, 3, 2);
static DateTime gNow;
static volatile int gNowLock = 0;
static volatile int gScheduleLock = 0;
static int gCurrentTemp = 0;
static int gHumidity = 0;
static int gTempArray[kTempArrayCount];
static int gTempIndex = 0;
static int gMaxTempIndex = 0;
static bool gHeatOn = false;
static int gInfoCounter = 0;
static int gLastScheduledTemp = -1;
static int gScheduleInEffect = 0;        // 0=none, 1..kScheduleOptionCount
static bool gOverrideTargetTemp = true;  // assume no schedule to start
static NVRam gMem;
static bool gPersistEEPROM = false;

void saveNVRam()
{  
  for (int i=0; i<kEEPROMSize; i++) {
    EEPROM.write(i, gMem.data[i]);
  }

  uint8_t *md5 = make_hash(gMem.data, kEEPROMSize);
  for (int i=kEEPROMSize; i<(kEEPROMSize + kEEPROMSignatureLen); i++) {
    EEPROM.write(i, *md5++);
  }
  
  log("NVRAM saved\n");
}

bool loadNVRam()
{
  for (int i=0; i<kEEPROMSize; i++) {
    gMem.data[i] = EEPROM.read(i);
  }

  uint8_t *md5 = gMem.checksum;
  for (int i=kEEPROMSize; i<(kEEPROMSize + kEEPROMSignatureLen); i++) {
    *md5++ = EEPROM.read(i);
  }

  md5 = make_hash(gMem.data, kEEPROMSize);
  if (!memcmp(md5, gMem.checksum, kEEPROMSignatureLen)) {
    log("NVRAM checksum matched\n");
  } else {
    log("NVRAM checksum did not match - loading defaults\n");
    
    memset(gMem.data, 0, kEEPROMSize);
    gMem.targetTemp = 70;
    
    saveNVRam();
    
    return false;
  }
  
  return true;
}

// returns pointer to static memory - not thread safe
uint8_t *getSignatureForBytes(uint8_t *bytes, uint16_t length, uint32_t key1, uint32_t key2)
{
    if (length > (kRequestMessageBaseLen + kRequestMessageMaxDataLen)) {
      return 0;
    }
 
    static uint8_t result[kSignatureLength];
    uint8_t data[kRequestMessageBaseLen + kRequestMessageMaxDataLen + 8];    // length = 4 bytes + key1 + key2
    memcpy(data, bytes, length);
    
    union long_hex lu;
    uint8_t *dest = &data[length];

    lu.lunsign = key1;
    *dest++ = lu.lbytes.b3;
    *dest++ = lu.lbytes.b2;
    *dest++ = lu.lbytes.b1;
    *dest++ = lu.lbytes.b0;

    lu.lunsign = key2;
    *dest++ = lu.lbytes.b3;
    *dest++ = lu.lbytes.b2;
    *dest++ = lu.lbytes.b1;
    *dest++ = lu.lbytes.b0;
    
    // create a half-length signature by XORing the two parts together
    uint8_t *fullSignature = make_hash((unsigned char*)data, length + 8);
    memcpy(result, fullSignature, kSignatureLength);
    for (int i=0; i<kSignatureLength; i++) {
      result[i] ^= fullSignature[kSignatureLength + i];
    }
    
    return result;
}

void setup()
{
  pinMode(kRTC5vPin, OUTPUT);        // sets Pin for HIGH output
  digitalWrite(kRTC5vPin, HIGH);     // turn pin on (5v) to power RTC
  pinMode(kRTCgndPin, OUTPUT);       // sets Pin for output
  digitalWrite(kRTCgndPin, LOW);     // turn pin on LOW (GND) to power RTC
  
  pinMode(kHeatOnPin, OUTPUT);
  digitalWrite(kHeatOnPin, HIGH);    // assume OFF initially
  
  pinMode(kButtonUpPin, INPUT_PULLUP);
  pinMode(kButtonDownPin, INPUT_PULLUP);
  
  for (int i=0; i<kTempArrayCount; i++) {
    gTempArray[i] = 0;
  }
  
  int seed = analogRead(1);
  randomSeed(seed);
  gKeyPart.lunsign = 0;
  
#ifdef USE_BLE_MINI
  BLEMini_begin(57600);
#else
  // Enable serial debug
  Serial.begin(57600);
  log("\n*** Thermo starting - random seed:");
  log(seed);
  log("\n");    
#endif  

  // configure the temp/humidity sensor
  gDht.begin();

  // configure the RTC
  if (!gRtc.begin()) {
    logWarn("couldn't find RTC\n");
  } else {  
    log("RTC initialized\n");
  }

  if (!gRtc.isrunning()) {
    logWarn("RTC is NOT running\n");
    // following line sets the RTC to the date & time this sketch was compiled
    gRtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
    // This line sets the RTC with an explicit date & time, for example to set
    // January 21, 2014 at 3am you would call:
    // gRtc.adjust(DateTime(2014, 1, 21, 3, 0, 0));
  } else {
    log("RTC running\n");
  }
  
  // set up the LCD's number of columns and rows: 
  gLcd.begin(16, 2);
  
  // read config from EEPROM
  loadNVRam();
  if ((gMem.targetTemp < kMinTargetTempF) || (gMem.targetTemp > kMaxTargetTempF)) {
    gMem.targetTemp = 70;
  }

  log("gMem.targetTemp: ");
  log(gMem.targetTemp);
  log("\n");
  
#ifndef USE_BLE_MINI
  // test
  gMem.weekdaySchedule.startTimeQuarterHours[0] = 22*4+1;      // 10:15pm
  gMem.weekdaySchedule.durationQuarterMinutes[0] = 2;
  gMem.weekdaySchedule.targetTemp[0] = 90;
  gMem.weekdaySchedule.startTimeQuarterHours[1] = 0;           // midnight
  gMem.weekdaySchedule.durationQuarterMinutes[1] = 24*4;       // whole day
  gMem.weekdaySchedule.targetTemp[1] = 60;
#endif  

  for (int sched=0; sched<2; sched++) {
    Schedule *s = (0==sched) ? &gMem.weekdaySchedule : &gMem.weekendSchedule;
    
    for (int i=0; i<kScheduleOptionCount; i++) {
      log((0==sched) ? "weekday schedule " : "weekend schedule ");
      log(i);
      log(": ");
      if (s->durationQuarterMinutes[i]) {
        log(s->startTimeQuarterHours[i]/4);
        log(":");
        log((s->startTimeQuarterHours[i]%4)*15);
        log(" for ");
        log(s->durationQuarterMinutes[i]*15);
        log(" min");
      } else {
        log("disabled");
      }
      log("\n");
    }  
  }
  
  Timer1.initialize(250000);             // initialize timer1, and set a 1/4 second period
  Timer1.attachInterrupt(timerCallback); // attaches callback() as a timer interrupt

  log("Timer1 setup\n");
}

int getAvgTemp()
{
  long sum = 0;
  
  for (int i=0; i<=gMaxTempIndex; i++) {
    sum += gTempArray[i];
  }
  
  return sum/(gMaxTempIndex + 1);
}

void getFriendlyTime(DateTime *dt, String *s)
{
  int hr = dt->hour();
  int min = dt->minute();
  int sec = dt->second();

  char *am_pm = " AM";  
  if (hr == 0) {
    hr = 12;  // midnight (12 AM)
  } else if (hr > 12) {
    hr -= 12;
    am_pm = " PM";
  } else if (hr == 12) {
    am_pm = " PM";
  }
  
  *s += hr;
  *s += ":";
  if (min < 10) {
    *s += "0";
  }
  *s += min;
  *s += ":";
  if (sec < 10) {
    *s += "0";
  }
  *s += sec;
  *s += am_pm;
}

// get target temp based on the current schedule, returns -1 for not found
// schedule priority is 0 (highest) to kScheduleOptionCount-1 (lowest)
int getScheduledTargetTemp(DateTime *dt, int *scheduleInEffect)
{
  int dow = dt->dayOfTheWeek();
  Schedule *s = ((kSaturday == dow) || (kSunday == dow)) ? &gMem.weekendSchedule : &gMem.weekdaySchedule;

  int minPastMidnight = dt->hour()*kMinutesPerHour + dt->minute();

  // return the first applicable target temp
  for (int i=0; i<kScheduleOptionCount; i++) {
    if (s->durationQuarterMinutes[i]) {
      // schedule is enabled
      int startMinPastMidnight = s->startTimeQuarterHours[i]*15;

//      log("minPastMidnight: ");
//      log(minPastMidnight);
//      log(", sched ");
//      log(i);
//      log(" - startMinPastMidnight: ");      
//      log(startMinPastMidnight);
//      log("\n");
      
      if ((minPastMidnight >= startMinPastMidnight) && (minPastMidnight < (startMinPastMidnight + s->durationQuarterMinutes[i]*15))) {
        *scheduleInEffect = i + 1; 
        return (int)s->targetTemp[i];
      }
    }
  }  
  
  *scheduleInEffect = 0;
  return -1;
}

void oneSecondTimer()
{
  // Temperature and humidity takes between 24 and 25 milliseconds
  // per http://playground.arduino.cc/Main/DHTLib
  float h = gDht.readHumidity();
  // Read temperature as Fahrenheit (isFahrenheit = true)
  float f = gDht.readTemperature(true);

  // Check if any reads failed and exit early (to try again).
  if (isnan(h) || isnan(f)) {
    logWarn("failed to read from DHT sensor\n");
    return;
  }

  // Compute heat index in Fahrenheit (the default)
  float hif = gDht.computeHeatIndex(f, h);
  
  gTempArray[gTempIndex] = round((f + hif)/2);
  gMaxTempIndex = MAX(gTempIndex, gMaxTempIndex);    
  if (++gTempIndex == kTempArrayCount) {
    gTempIndex = 0;
  }
    
  gCurrentTemp = getAvgTemp();
  gHumidity = (int)h;

  if (!gScheduleLock) {
    // if scheduled temp has changed (and is enabled), put it into effect and clear any override
    int scheduledTemp = getScheduledTargetTemp(&gNow, &gScheduleInEffect);
    if (scheduledTemp != gLastScheduledTemp) {
      gLastScheduledTemp = scheduledTemp;
      if (gLastScheduledTemp != -1) {
        gMem.targetTemp = gLastScheduledTemp;
        gOverrideTargetTemp = false;   
      }
    }
  } // else - we'll get it next time

  log("Humidity: ");
  log(h);
  log(" %, Temp: ");
  log(f);
  log(" deg F, Heat index: ");
  log(hif);
  log(" deg F, Avg: ");  
  log(gCurrentTemp);
  log(" deg F, Target: ");
  log(gMem.targetTemp);
  log(" deg F, Schedule: ");
  log(gScheduleInEffect);
  log(", Override: ");  
  log(gOverrideTargetTemp);
  log("\n");
  
  String tempString = "Tmp ";
  tempString += gCurrentTemp;
  tempString += "F, RH ";
  tempString += gHumidity;
  tempString += "%  ";

  gLcd.setCursor(0, 0);
  gLcd.print(kLCDBlankLine);
  gLcd.setCursor(0, 0);
  gLcd.print(tempString);

  // alternate between displaying the time and the target temp
  if (++gInfoCounter >= 4) {
    gInfoCounter = 0;
  }

  String targetString;  
  if (gInfoCounter < 2) {
    targetString = (gOverrideTargetTemp || !gScheduleInEffect) ? "Manual tmp: " : "Sched tmp: ";
    targetString += gMem.targetTemp;
  } else {
    if (!gNowLock) {      
      getFriendlyTime(&gNow, &targetString);
    }
  }
  
  gLcd.setCursor(0, 1);
  gLcd.print(kLCDBlankLine);
  gLcd.setCursor(0, 1);  // set the cursor to column 0, line 1
  gLcd.print(targetString);

  if (gCurrentTemp < gMem.targetTemp) {
    gHeatOn = true;
    digitalWrite(kHeatOnPin, LOW);  // active low == heat on
  } else if (gCurrentTemp > gMem.targetTemp) {
    gHeatOn = false;
    digitalWrite(kHeatOnPin, HIGH);
  } // else leave at prev state if == target temp
}

void timerCallback()
{
  // scan buttons frequently
  int buttonDown = digitalRead(kButtonDownPin) ? 0 : 1;
  int buttonUp = digitalRead(kButtonUpPin) ? 0 : 1;

  bool changedTemp = false;
  if (buttonDown) {
    if (gMem.targetTemp > kMinTargetTempF) {
      gMem.targetTemp -= 1;
      changedTemp = true;
    }
  } else if (buttonUp) {
    if (gMem.targetTemp < kMaxTargetTempF) {
      gMem.targetTemp += 1;
      changedTemp = true;
    }
  }  

  if (changedTemp) {
    gPersistEEPROM = true;       // target temp modified
    
    gInfoCounter = 0;            // display target temp while editing
    String targetString;  
    targetString = "Manual tmp: ";
    targetString += gMem.targetTemp;
    
    gLcd.setCursor(0, 1);
    gLcd.print(kLCDBlankLine);
    gLcd.setCursor(0, 1);        // set the cursor to column 0, line 1
    gLcd.print(targetString);
    
    gOverrideTargetTemp = true;  // override until the schedule kicks in
  }
  
  // do other things less frequently
  static int secondCount = 0;
  if (++secondCount >= 4) {
    secondCount = 0;
    oneSecondTimer();
  }
}

void loop()
{
  static bool firstPass = true;
  static unsigned long lastReadRTCTime = 0;
  unsigned long now = millis();
  
  unsigned deltaMs;
  if (now > lastReadRTCTime) {
    deltaMs = (now - lastReadRTCTime);
  } else {
    // now < lastReadRTCTime
    deltaMs = (0xFFFFFFFFUL - lastReadRTCTime + now);
  }

  if (firstPass || (deltaMs > 1000)) {
    // reading the RTC in the timer doesn't seem to work, and the arduino doesn't have
    // real synchronization primitives, so I use a poor mans' lock here:
    gNowLock = 1;
    gNow = gRtc.now();
    gNowLock = 0;
    
    // also sync to EEPROM if needed
    if (gPersistEEPROM) {
      gPersistEEPROM = false;
      saveNVRam();
    }
    
    firstPass = false;
    lastReadRTCTime = now;
  }

#ifdef USE_BLE_MINI
  // have at least one byte in the rx buffer
  int rxLen = ble_available();
  if (rxLen) {  
    delay(10);                // more than long enough to get the max msg len at 57600 bps
    rxLen = ble_available();  // how many do we have now?

    // request msg format: [ ... signature ... ][cmd][seq][data len][ ... data ... ]
    bool lengthError = false;    
    if (rxLen < (kSignatureLength + kRequestMessageBaseLen) /* min msg len */) {
      lengthError = true;
    } else {
      uint8_t payload[kRequestMessageBaseLen + kRequestMessageMaxDataLen];
      uint8_t rx_signature[kSignatureLength];
      
      for (int i=0; i<kSignatureLength; i++) {
        rx_signature[i] = ble_read();
      }
  
      uint8_t command = payload[0] = ble_read();
      uint8_t sequence = payload[1] = ble_read();
      uint8_t dataLen = payload[2] = ble_read();
      dataLen = MIN(dataLen, kRequestMessageMaxDataLen);
      
      // now check if we have enough data bytes
      if (rxLen < (kSignatureLength + kRequestMessageBaseLen + dataLen)) {
        lengthError = true;
      } else {      
        for (int i=0; i<dataLen; i++) {
          payload[kRequestMessageBaseLen + i] = ble_read();
        }
        
        bool signature_matched = false;
        if (gKeyPart.lunsign) {
          uint8_t *calc_signature = getSignatureForBytes(payload, kRequestMessageBaseLen + dataLen, kSharedKey, gKeyPart.lunsign);    
          signature_matched = !memcmp(calc_signature, rx_signature, kSignatureLength);
        }
          
        uint8_t *p = &payload[kRequestMessageBaseLen];
        bool forWeekdaySchedule = false;
        switch (command) {
          case kCmdGetKeyPart:
            gKeyPart.lunsign = random(0x7FFFFFFF);
    
            log("kCmdGetKeyPart: ");
            log(gKeyPart.lunsign, HEX);
            log("\n");    
    
            ble_write(kResponseSignature);
            ble_write(sequence);
            ble_write(kResponseOK);           
            ble_write(4);  // data length
            ble_write(gKeyPart.lbytes.b3);
            ble_write(gKeyPart.lbytes.b2);
            ble_write(gKeyPart.lbytes.b1);
            ble_write(gKeyPart.lbytes.b0);         
            break;
    
          case kCmdGetTemps: {
            union hex u;
            
            ble_write(kResponseSignature);
            ble_write(sequence);
            ble_write(kResponseOK);           
            ble_write(7);  // data length
    
            ble_write(gHeatOn);
            
            u.unsign = gCurrentTemp;
            ble_write(u.byte.high);         
            ble_write(u.byte.low);         
    
            ble_write(gHumidity);
    
            u.unsign = gMem.targetTemp;
            ble_write(u.byte.high);                 
            ble_write(u.byte.low);         
    
            uint8_t activeSchedule = (gOverrideTargetTemp ? 0 : gScheduleInEffect);
            ble_write(activeSchedule);
            break;
          }
    
          case kCmdSetTargetTemp: {
            bool success = false;
            if (signature_matched) {
              gMem.targetTemp = (int)*p++;          
              
              // override until the schedule kicks in
              gOverrideTargetTemp = true;  
    
              // reset key for next time
              gKeyPart.lunsign = 0;
              success = true;
    
              gPersistEEPROM = true;  // target temp modified
            }        
            
            ble_write(kResponseSignature);
            ble_write(sequence);
            ble_write(success ? kResponseOK : kResponseErrorSig);           
            ble_write(0);  // data length
            break;
          }
          
          case kCmdSetDateTime: {
            bool success = false;
            if (signature_matched) {
              union hex u;
      
              u.byte.high = *p++;
              u.byte.low = *p++;    // year (ex: 2016)
              uint8_t month = *p++;
              uint8_t day = *p++;
              uint8_t hour = *p++;
              uint8_t min = *p++;
              
              gRtc.adjust(DateTime(u.unsign, month, day, hour, min, 0));
    
              // reset key for next time
              gKeyPart.lunsign = 0;
              success = true;
            }
    
            ble_write(kResponseSignature);
            ble_write(sequence);
            ble_write(success ? kResponseOK : kResponseErrorSig);           
            ble_write(0);  // data length
            break;
          }
    
          case kCmdGetWeekdayTempSchedule:
            forWeekdaySchedule = true;
            // continue
          case kCmdGetWeekendTempSchedule: {
            ble_write(kResponseSignature);
            ble_write(sequence);
            ble_write(kResponseOK);           
            ble_write(9);  // data length
    
            Schedule *s = forWeekdaySchedule ? &gMem.weekdaySchedule : &gMem.weekendSchedule; 
            for (int i=0; i<kScheduleOptionCount; i++) {
              ble_write(s->startTimeQuarterHours[i]);
              ble_write(s->durationQuarterMinutes[i]);
              ble_write(s->targetTemp[i]);
            }      
            break;
          }
    
          case kCmdSetWeekdayTempSchedule:
            forWeekdaySchedule = true;
            // continue
          case kCmdSetWeekendTempSchedule: {
            bool success = false;
            if (signature_matched) {
              gScheduleLock = 1;
              Schedule *s = forWeekdaySchedule ? &gMem.weekdaySchedule : &gMem.weekendSchedule; 
              for (int i=0; i<kScheduleOptionCount; i++) {
                s->startTimeQuarterHours[i] = *p++;
                s->durationQuarterMinutes[i] = *p++;
                s->targetTemp[i] = *p++;
              }      
              gScheduleLock = 0;
              
              // reset key for next time
              gKeyPart.lunsign = 0;
              success = true;
              
              gPersistEEPROM = true;  // schedule modified
            }
    
            ble_write(kResponseSignature);
            ble_write(sequence);
            ble_write(success ? kResponseOK : kResponseErrorSig);           
            ble_write(0);  // data length
            break;
          }
            
          default:
            log("Invalid command: ");
            log(command);
            log("\n");
    
            ble_write(kResponseSignature);
            ble_write(sequence);
            ble_write(kResponseErrorInvalidCommand);           
            ble_write(0);  // data length
            break;      
        }
      }
    }

    if (lengthError) {
      ble_write(kResponseSignature);
      ble_write(0xAA);
      ble_write(kResponseErrorInvalidLength);           
      ble_write(1);      // data length
      ble_write(rxLen);  // how many bytes we got
      
      // drain the rx buffer
      while (ble_available()) {
        (void)ble_read();
      }
    }     
  }    
#endif
}

