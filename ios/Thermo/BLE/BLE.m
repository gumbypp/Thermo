
/*
 
 Copyright (c) 2013 RedBearLab
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
*/

#import "BLE.h"
#import "BLEDefines.h"

@interface BLE  ()

@property (strong, nonatomic) CBCentralManager *CM;
@property (strong, nonatomic) NSString *discoverName;

@end

@implementation BLE

static bool isConnected = false;
static int rssi = 0;

- (void)readRSSI
{
    [self.activePeripheral readRSSI];
}

- (BOOL)isConnected
{
    return isConnected;
}

- (BOOL)read
{
    CBUUID *uuid_service = [CBUUID UUIDWithString:@RBL_SERVICE_UUID];
    CBUUID *uuid_char = [CBUUID UUIDWithString:@RBL_CHAR_TX_UUID];
    
    return [self readValue:uuid_service characteristicUUID:uuid_char p:self.activePeripheral];
}

- (BOOL)write:(NSData *)d
{
    CBUUID *uuid_service = [CBUUID UUIDWithString:@RBL_SERVICE_UUID];
    CBUUID *uuid_char = [CBUUID UUIDWithString:@RBL_CHAR_RX_UUID];
    
    return [self writeValue:uuid_service characteristicUUID:uuid_char p:self.activePeripheral data:d];
}

- (void)enableReadNotification:(CBPeripheral *)p
{
    CBUUID *uuid_service = [CBUUID UUIDWithString:@RBL_SERVICE_UUID];
    CBUUID *uuid_char = [CBUUID UUIDWithString:@RBL_CHAR_TX_UUID];
    
    [self notification:uuid_service characteristicUUID:uuid_char p:p on:YES];
}

- (BOOL)notification:(CBUUID *)serviceUUID characteristicUUID:(CBUUID *)characteristicUUID p:(CBPeripheral *)p on:(BOOL)on
{
    CBService *service = [self findServiceFromUUID:serviceUUID p:p];
    
    if (!service) {
        NSLogWarn(@"Could not find service with UUID %@ on peripheral with UUID %@",
                  serviceUUID,
                  p.identifier.UUIDString);
        
        return NO;
    }
    
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service];
    
    if (!characteristic) {
        NSLogWarn(@"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                  characteristicUUID,
                  serviceUUID,
                  p.identifier.UUIDString);
        
        return NO;
    }
    
    [p setNotifyValue:on forCharacteristic:characteristic];
    
    return YES;
}

- (UInt16)frameworkVersion
{
    return RBL_BLE_FRAMEWORK_VER;
}

- (BOOL)readValue:(CBUUID *)serviceUUID characteristicUUID:(CBUUID *)characteristicUUID p:(CBPeripheral *)p
{
    CBService *service = [self findServiceFromUUID:serviceUUID p:p];
    
    if (!service) {
        NSLogWarn(@"Could not find service with UUID %@ on peripheral with UUID %@",
                  serviceUUID,
                  p.identifier.UUIDString);
        
        return NO;
    }
    
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service];
    
    if (!characteristic) {
        NSLogWarn(@"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                  characteristicUUID,
                  serviceUUID,
                  p.identifier.UUIDString);
        
        return NO;
    }
    
    [p readValueForCharacteristic:characteristic];
    
    return YES;
}

- (BOOL)writeValue:(CBUUID *)serviceUUID characteristicUUID:(CBUUID *)characteristicUUID p:(CBPeripheral *)p data:(NSData *)data
{
    CBService *service = [self findServiceFromUUID:serviceUUID p:p];
    
    if (!service) {
        NSLogWarn(@"Could not find service with UUID %@ on peripheral with UUID %@",
                  serviceUUID,
                  p.identifier.UUIDString);
        
        return NO;
    }
    
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service];
    
    if (!characteristic) {
        NSLogWarn(@"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                  characteristicUUID,
                  serviceUUID,
                  p.identifier.UUIDString);
        
        return NO;
    }
    
    [p writeValue:data forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
    
    return YES;
}

- (UInt16)swap:(UInt16)s
{
    UInt16 temp = s << 8;
    temp |= (s >> 8);
    return temp;
}

- (void)controlSetup
{
    self.CM = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
}

- (int)findBLEPeripheralsWithName:(NSString *)name
{
    if (self.CM.state != CBCentralManagerStatePoweredOn) {
        NSLogWarn(@"CoreBluetooth not correctly initialized !");
        NSLogWarn(@"State = %d (%s)", self.CM.state, [self centralManagerStateToString:self.CM.state]);
        return -1;
    }
    
#if TARGET_OS_IPHONE
    [self.CM scanForPeripheralsWithServices:[NSArray arrayWithObject:[CBUUID UUIDWithString:@RBL_SERVICE_UUID]] options:nil];
#else
    [self.CM scanForPeripheralsWithServices:nil options:nil]; // Start scanning
#endif
    
    NSLogDebug(@"scanForPeripheralsWithServices");
    
    self.discoverName = name;
    
    return 0; // Started scanning OK !
}

- (void)stopFindingPeripherals
{
    [self.CM stopScan];
    
    NSLogDebug(@"Stopped Scanning");
    NSLogDebug(@"Known peripherals : %lu", (unsigned long)[self.peripherals count]);
    
    [self printKnownPeripherals];
}

- (void)connectPeripheral:(CBPeripheral *)peripheral
{
    NSLogDebug(@"Connecting to peripheral with UUID : %@", peripheral.identifier.UUIDString);
    
    [self.CM connectPeripheral:peripheral
                       options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
    self.connectingPeripheral = peripheral;
}

- (void)disconnectPeripheral:(CBPeripheral *)peripheral
{
    [self.CM cancelPeripheralConnection:peripheral];
    self.connectingPeripheral = nil;
}

- (const char *)centralManagerStateToString:(int)state
{
    switch(state)
    {
        case CBCentralManagerStateUnknown:
            return "State unknown (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateResetting:
            return "State resetting (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateUnsupported:
            return "State BLE unsupported (CBCentralManagerStateResetting)";
        case CBCentralManagerStateUnauthorized:
            return "State unauthorized (CBCentralManagerStateUnauthorized)";
        case CBCentralManagerStatePoweredOff:
            return "State BLE powered off (CBCentralManagerStatePoweredOff)";
        case CBCentralManagerStatePoweredOn:
            return "State powered up and ready (CBCentralManagerStatePoweredOn)";
        default:
            return "State unknown";
    }
    
    return "Unknown state";
}

- (void)printKnownPeripherals
{
    NSLogDebug(@"List of currently known peripherals :");
    
    for (int i = 0; i < self.peripherals.count; i++) {
        CBPeripheral *p = [self.peripherals objectAtIndex:i];
        
        if (p.identifier != NULL) {
            NSLogDebug(@"%d  |  %@", i, p.identifier.UUIDString);
        } else {
            NSLogDebug(@"%d  |  NULL", i);
        }
        
        [self printPeripheralInfo:p];
    }
}

- (void)printPeripheralInfo:(CBPeripheral*)peripheral
{
    NSLogDebug(@"------------------------------------");
    NSLogDebug(@"Peripheral Info :");
    
    if (peripheral.identifier != NULL) {
        NSLogDebug(@"UUID : %@", peripheral.identifier.UUIDString);
    } else {
        NSLogDebug(@"UUID : NULL");
    }
    
    NSLogDebug(@"Name : %@", peripheral.name);
    NSLogDebug(@"-------------------------------------");
}

- (BOOL)UUIDSAreEqual:(NSUUID *)UUID1 UUID2:(NSUUID *)UUID2
{
    if ([UUID1.UUIDString isEqualToString:UUID2.UUIDString]) {
        return TRUE;
    }
    
    return FALSE;
}

- (void)getTxRxCharacteristicsFromPeripheral:(CBPeripheral *)p
{
    for (int i=0; i < p.services.count; i++) {
        CBService *s = [p.services objectAtIndex:i];
        
        if ([s.UUID isEqual:[CBUUID UUIDWithString:@RBL_SERVICE_UUID]]) {
            NSLogDebug(@"Fetching tx/rx characteristics for service with UUID %@", s.UUID);

            [p discoverCharacteristics:@[[CBUUID UUIDWithString:@RBL_CHAR_TX_UUID], [CBUUID UUIDWithString:@RBL_CHAR_RX_UUID]]
                            forService:s];
        }
    }
}

- (int)compareCBUUID:(CBUUID *)UUID1 UUID2:(CBUUID *)UUID2
{
    char b1[16];
    char b2[16];
    [UUID1.data getBytes:b1];
    [UUID2.data getBytes:b2];
    
    if (memcmp(b1, b2, UUID1.data.length) == 0) {
        return 1;
    } else {
        return 0;
    }
}

- (CBUUID *)IntToCBUUID:(UInt16)UUID
{
    char t[16];
    t[0] = ((UUID >> 8) & 0xff); t[1] = (UUID & 0xff);
    NSData *data = [[NSData alloc] initWithBytes:t length:16];
    return [CBUUID UUIDWithData:data];
}

- (CBService *)findServiceFromUUID:(CBUUID *)UUID p:(CBPeripheral *)p
{
    for (int i = 0; i < p.services.count; i++) {
        CBService *s = [p.services objectAtIndex:i];
        if ([self compareCBUUID:s.UUID UUID2:UUID]) {
            return s;
        }
    }
    
    return nil; //Service not found on this peripheral
}

- (CBCharacteristic *)findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service
{
    for (int i=0; i < service.characteristics.count; i++) {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        if ([self compareCBUUID:c.UUID UUID2:UUID]) {
            return c;
        }
    }
    
    return nil; //Characteristic not found on this service
}

#if TARGET_OS_IPHONE
    //-- no need for iOS
#else
- (BOOL)isLECapableHardware
{
    NSString * state = nil;
    
    switch ([CM state]) {
        case CBCentralManagerStateUnsupported:
            state = @"The platform/hardware doesn't support Bluetooth Low Energy.";
            break;
            
        case CBCentralManagerStateUnauthorized:
            state = @"The app is not authorized to use Bluetooth Low Energy.";
            break;
            
        case CBCentralManagerStatePoweredOff:
            state = @"Bluetooth is currently powered off.";
            break;
            
        case CBCentralManagerStatePoweredOn:
            return TRUE;
            
        case CBCentralManagerStateUnknown:
        default:
            return FALSE;
            
    }
    
    NSLogDebug(@"Central manager state: %@", state);
        
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:state];
    [alert addButtonWithTitle:@"OK"];
    [alert setIcon:[[NSImage alloc] initWithContentsOfFile:@"AppIcon"]];
    [alert beginSheetModalForWindow:nil modalDelegate:self didEndSelector:nil contextInfo:nil];
    
    return FALSE;
}
#endif

#pragma mark - CBCentralManagerDelegate methods

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
#if TARGET_OS_IPHONE
    NSLogDebug(@"Status of CoreBluetooth central manager changed %d (%s)", central.state, [self centralManagerStateToString:central.state]);
#else
    [self isLECapableHardware];
#endif
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    // this is more reliable than peripheral.name
    NSString *peripheralName = advertisementData[@"kCBAdvDataLocalName"];
    
    NSLogDebug(@"found: %@", peripheralName);
    if (self.discoverName && ![peripheralName isEqualToString:self.discoverName]) {
        return;
    }
    
    if (!self.peripherals) {
        self.peripherals = [[NSMutableArray alloc] initWithObjects:peripheral,nil];
        [[self delegate] ble:self didDiscoverPeripheral:peripheral];
    } else {
        for (int i = 0; i < self.peripherals.count; i++) {
            CBPeripheral *p = [self.peripherals objectAtIndex:i];
            
            if ((p.identifier == NULL) || (peripheral.identifier == NULL)) {
                continue;
            }
            
            if ([self UUIDSAreEqual:p.identifier UUID2:peripheral.identifier]) {
                [self.peripherals replaceObjectAtIndex:i withObject:peripheral];
                NSLogDebug(@"Duplicate UUID found updating...");
                return;
            }
        }
        
        [self.peripherals addObject:peripheral];
        [[self delegate] ble:self didDiscoverPeripheral:peripheral];
        
        NSLogDebug(@"New UUID, adding");
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    if (peripheral.identifier != NULL) {
        NSLogDebug(@"Connected to %@ successful", peripheral.identifier.UUIDString);
    } else {
        NSLogDebug(@"Connected to NULL successful");
    }
    
    self.activePeripheral = peripheral;
    self.activePeripheral.delegate = self;
    [self.activePeripheral discoverServices:@[[CBUUID UUIDWithString:@RBL_SERVICE_UUID]]];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error;
{
    self.connectingPeripheral = nil;

    NSLogDebug(@"error: %@", error);
    
    done = false;
    
    self.activePeripheral = nil;
    [[self delegate] ble:self didDisconnectPeripheral:peripheral];
    isConnected = false;
}


static bool done = false;

#pragma mark - CBPeripheralDelegate methods

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if (!error) {
        NSLogDebug(@"Characteristics of service with UUID %@ found", service.UUID);
        
        for (int i=0; i < service.characteristics.count; i++) {
            CBCharacteristic *c = [service.characteristics objectAtIndex:i];
            NSLogDebug(@"Found characteristic %@", c.UUID);
            CBService *s = [peripheral.services objectAtIndex:(peripheral.services.count - 1)];
            
            if ([service.UUID isEqual:s.UUID]) {
                if (!done) {
                    self.connectingPeripheral = nil;
                    [self enableReadNotification:self.activePeripheral];
                    [[self delegate] ble:self didConnectPeripheral:peripheral];
                    isConnected = true;
                    done = true;
                }
                break;
            }
        }
    } else {
        NSLogDebug(@"Characteristic discorvery unsuccessful!");
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (!error) {
        NSLogDebug(@"Services of peripheral with UUID : %@ found", peripheral.identifier.UUIDString);
        [self getTxRxCharacteristicsFromPeripheral:peripheral];
    } else {
        NSLogWarn(@"Service discovery was unsuccessful!");
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (!error) {
        NSLogDebug(@"Updated notification state for characteristic with UUID %@ on service with  UUID %@ on peripheral with UUID %@",
                   characteristic.UUID, characteristic.service.UUID, peripheral.identifier.UUIDString);
    } else {
        NSLogWarn(@"Error in setting notification state for characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                  characteristic.UUID,
                  characteristic.service.UUID,
                  peripheral.identifier.UUIDString);
        
        NSLogDebug(@"Error code was %s", [[error description] cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    unsigned char data[20];
    
    static unsigned char buf[512];
    static int len = 0;
    NSInteger data_len;
    
    if (!error) {
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@RBL_CHAR_TX_UUID]]) {
            data_len = characteristic.value.length;
            [characteristic.value getBytes:data length:data_len];
            
            if (data_len == 20) {
                memcpy(&buf[len], data, 20);
                len += data_len;
                
                if (len >= 64) {
                    [[self delegate] ble:self peripheral:peripheral didReceiveData:buf length:len];
                    len = 0;
                }
            } else if (data_len < 20) {
                memcpy(&buf[len], data, data_len);
                len += data_len;
                
                [[self delegate] ble:self peripheral:peripheral didReceiveData:buf length:len];
                len = 0;
            }
        }
    } else {
        NSLogWarn(@"updateValueForCharacteristic failed!");
    }
}

- (void)peripheralDidUpdateRSSI:(CBPeripheral *)peripheral error:(NSError *)error
{
    if (!isConnected) {
        return;
    }
    
    if (rssi != peripheral.RSSI.intValue) {
        rssi = peripheral.RSSI.intValue;
        [[self delegate] ble:self peripheral:peripheral didUpdateRSSI:self.activePeripheral.RSSI];
    }
}

@end
