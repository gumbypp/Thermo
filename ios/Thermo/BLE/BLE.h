
/*
 
 Copyright (c) 2013 RedBearLab
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
*/

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
    #import <CoreBluetooth/CoreBluetooth.h>
#else
    #import <IOBluetooth/IOBluetooth.h>
#endif

@class BLE;

@protocol BLEDelegate
@required
- (void)ble:(BLE *)ble didDiscoverPeripheral:(CBPeripheral *)peripheral;
- (void)ble:(BLE *)ble didConnectPeripheral:(CBPeripheral *)peripheral;
- (void)ble:(BLE *)ble didDisconnectPeripheral:(CBPeripheral *)peripheral;
- (void)ble:(BLE *)ble peripheral:(CBPeripheral *)peripheral didUpdateRSSI:(NSNumber *)rssi;
- (void)ble:(BLE *)ble peripheral:(CBPeripheral *)peripheral didReceiveData:(unsigned char *)data length:(int)length;
@end

@interface BLE : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate> {
    
}

@property (nonatomic,assign) id <BLEDelegate> delegate;
@property (strong, nonatomic) NSMutableArray *peripherals;
@property (strong, nonatomic) CBPeripheral *connectingPeripheral;
@property (strong, nonatomic) CBPeripheral *activePeripheral;

- (void)enableReadNotification:(CBPeripheral *)p;
- (BOOL)read;
- (BOOL)writeValue:(CBUUID *)serviceUUID characteristicUUID:(CBUUID *)characteristicUUID p:(CBPeripheral *)p data:(NSData *)data;

- (BOOL)isConnected;
- (BOOL)write:(NSData *)d;
- (void)readRSSI;

- (void)controlSetup;
- (int)findBLEPeripheralsWithName:(NSString *)name;
- (void)stopFindingPeripherals;
- (void)connectPeripheral:(CBPeripheral *)peripheral;
- (void)disconnectPeripheral:(CBPeripheral *)peripheral;

- (UInt16)swap:(UInt16)s;
- (const char *)centralManagerStateToString:(int)state;
- (void)printKnownPeripherals;
- (void)printPeripheralInfo:(CBPeripheral*)peripheral;

- (void)getTxRxCharacteristicsFromPeripheral:(CBPeripheral *)p;
- (CBService *)findServiceFromUUID:(CBUUID *)UUID p:(CBPeripheral *)p;
- (CBCharacteristic *)findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service;

- (int)compareCBUUID:(CBUUID *)UUID1 UUID2:(CBUUID *)UUID2;
- (BOOL)UUIDSAreEqual:(NSUUID *)UUID1 UUID2:(NSUUID *)UUID2;

@end
