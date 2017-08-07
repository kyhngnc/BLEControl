//
//  BluetoothSerial.swift (originally DZBluetoothSerialHandler.swift)
//  HM10 Serial
//
//  Created by Alex on 09-08-15.
//  Copyright (c) 2017 Hangar42. All rights reserved.
//
//

import UIKit
import CoreBluetooth

// Remote Device and Service:
// <CBPeripheral: 0x1700f1300, identifier = 37CA0C86-969A-4225-A781-A9D1DC9AECD6, name = Car-CC2541, state = connected>
// <CBService: 0x170271a00, isPrimary = YES, UUID = FFE0>
// <CBCharacteristic: 0x1740a5be0, UUID = FFE1, properties = 0x1E, value = (null), notifying = NO>

/// Global serial handler, don't forget to initialize it with init(delgate:)
var serial: BluetoothSerial!

// Delegate functions
protocol BluetoothSerialDelegate {
    // ** Required **
    
    /// Called when de state of the CBCentralManager changes (e.g. when bluetooth is turned on/off)
    func serialDidChangeState()
    
    /// Called when a peripheral disconnected
    func serialDidDisconnect(_ peripheral: CBPeripheral, error: NSError?)
    
    // ** Optionals **
    
    /// Called when a message is received
    func serialDidReceiveString(_ message: String)
    
    /// Called when a message is received
    func serialDidReceiveBytes(_ bytes: [UInt8])
    
    /// Called when a message is received
    func serialDidReceiveData(_ data: Data)
    
    /// Called when a message is sent
    func serialDidSendString(_ message: String)
    
    /// Called when a message is sent
    func serialDidSendBytes(_ bytes: [UInt8])
    
    /// Called when a message is sent
    func serialDidSendData(_ data: Data)
    
    /// Called when the RSSI of the connected peripheral is read
    func serialDidReadRSSI(_ rssi: NSNumber)
    
    /// Called when a new peripheral is discovered while scanning. Also gives the RSSI (signal strength)
    func serialDidDiscoverPeripheral(_ peripheral: CBPeripheral, RSSI: NSNumber?)
    
    /// Called when a peripheral is connected (but not yet ready for cummunication)
    func serialDidConnect(_ peripheral: CBPeripheral)
    
    /// Called when a pending connection failed
    func serialDidFailToConnect(_ peripheral: CBPeripheral, error: NSError?)

    /// Called when a peripheral is ready for communication
    func serialIsReady(_ peripheral: CBPeripheral)
}

// Make some of the delegate functions optional
extension BluetoothSerialDelegate {
    func serialDidReceiveString(_ message: String) {}
    func serialDidReceiveBytes(_ bytes: [UInt8]) {}
    func serialDidReceiveData(_ data: Data) {}
    func serialDidSendString(_ message: String) {}
    func serialDidSendBytes(_ bytes: [UInt8]) {}
    func serialDidSendData(_ data: Data) {}
    func serialDidReadRSSI(_ rssi: NSNumber) {}
    func serialDidDiscoverPeripheral(_ peripheral: CBPeripheral, RSSI: NSNumber?) {}
    func serialDidConnect(_ peripheral: CBPeripheral) {}
    func serialDidFailToConnect(_ peripheral: CBPeripheral, error: NSError?) {}
    func serialIsReady(_ peripheral: CBPeripheral) {}
}


final class BluetoothSerial: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    let carUUID = CBUUID(string:"37CA0C86-969A-4225-A781-A9D1DC9AECD6")
    // MARK: Variables
    
    /// The delegate object the BluetoothDelegate methods will be called upon
    var delegate: BluetoothSerialDelegate!{
        didSet{
            print("delegate:old=\(oldValue),new=\(delegate)")
        }
    }
    
    /// The CBCentralManager this bluetooth serial handler uses for... well, everything really
    var centralManager: CBCentralManager!
    
    /// The peripheral we're trying to connect to (nil if none)
    var pendingPeripheral: CBPeripheral?
    
    /// The connected peripheral (nil if none is connected)
    var connectedPeripheral: CBPeripheral?

    /// The characteristic 0xFFE1 we need to write to, of the connectedPeripheral
    weak var writeCharacteristic: CBCharacteristic?
    
    /// Whether this serial is ready to send and receive data
    var isReady: Bool {
        get {
            return centralManager.state == .poweredOn &&
                   connectedPeripheral != nil &&
                   writeCharacteristic != nil
        }
    }
    
    /// Whether this serial is looking for advertising peripherals
    var isScanning: Bool {
        return centralManager.isScanning
    }
    
    /// Whether the state of the centralManager is .poweredOn
    var isPoweredOn: Bool {
        return centralManager.state == .poweredOn
    }
    
    /// UUID of the service to look for.
    var serviceUUID = CBUUID(string: "FFE0")
    
    /// UUID of the characteristic to look for.
    var characteristicUUID = CBUUID(string: "FFE1")
    
    var testServiceUUID = CBUUID(string: "FFF0")
    var testCharacteristicUUID = CBUUID(string: "FFF1")
    
    /// Whether to write to the HM10 with or without response. Set automatically.
    /// Legit HM10 modules (from JNHuaMao) require 'Write without Response',
    /// while fake modules (e.g. from Bolutek) require 'Write with Response'.
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    
    
    // MARK: functions
    
    /// Always use this to initialize an instance
    init(delegate: BluetoothSerialDelegate) {
        super.init()
        print("init:")
        self.delegate = delegate
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    /// Start scanning for peripherals
    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        print("startScan:")
        // start scanning for peripherals with correct service UUID
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        
        // retrieve peripherals that are already connected
        // see this stackoverflow question http://stackoverflow.com/questions/13286487
        let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])
        for peripheral in peripherals {
            delegate.serialDidDiscoverPeripheral(peripheral, RSSI: nil)
        }
    }
    
    /// Stop scanning for peripherals
    func stopScan() {
        print("stopScan:")
        centralManager.stopScan()
    }
    
    /// Try to connect to the given peripheral
    func connectToPeripheral(_ peripheral: CBPeripheral) {
        print("connectToPeripheral:\(peripheral)")
        pendingPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }
    
    /// Disconnect from the connected peripheral or stop connecting to it
    func disconnect() {
        print("disconnect:")
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        } else if let p = pendingPeripheral {
            centralManager.cancelPeripheralConnection(p) //TODO: Test whether its neccesary to set p to nil
        }
    }
    
    /// The didReadRSSI delegate function will be called after calling this function
    func readRSSI() {
        print("readRSSI:")
        guard isReady else { return }
        connectedPeripheral!.readRSSI()
    }
    
    /// Send a string to the device
    func sendMessageToDevice(_ message: String) {
        print("sendMessageToDevice:\(message)")
        guard isReady else { return }
        
        if let data = message.data(using: String.Encoding.utf8) {
            connectedPeripheral!.writeValue(data, for: writeCharacteristic!, type: writeType)
        }
    }
    
    /// Send an array of bytes to the device
    func sendBytesToDevice(_ bytes: [UInt8]) {
        print("sendBytesToDevice:\(bytes)")
        guard isReady else { return }
        
        let data = Data(bytes: UnsafePointer<UInt8>(bytes), count: bytes.count)
        connectedPeripheral!.writeValue(data, for: writeCharacteristic!, type: writeType)
    }
    
    /// Send data to the device
    func sendDataToDevice(_ data: Data) {
        print("sendDataToDevice:\(data)")
        guard isReady else { return }
        
        connectedPeripheral!.writeValue(data, for: writeCharacteristic!, type: writeType)
    }
    
    
    // MARK: CBCentralManagerDelegate functions

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        print("didDiscover:\(peripheral)")
        // just send it to the delegate
        delegate.serialDidDiscoverPeripheral(peripheral, RSSI: RSSI)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("didConnect:\(peripheral)")
        // set some stuff right
        peripheral.delegate = self
        pendingPeripheral = nil
        connectedPeripheral = peripheral
        
        // send it to the delegate
        delegate.serialDidConnect(peripheral)
        NotificationCenter.default.post(name: .BluetoothDidStateChange, object: self)

        // Okay, the peripheral is connected but we're not ready yet!
        // First get the 0xFFE0 service
        // Then get the 0xFFE1 characteristic of this service
        // Subscribe to it & create a weak reference to it (for writing later on), 
        // and find out the writeType by looking at characteristic.properties.
        // Only then we're ready for communication

        peripheral.discoverServices([serviceUUID, testServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("didDisconnectPeripheral:\(peripheral) \(error)")
        connectedPeripheral = nil
        pendingPeripheral = nil

        // send it to the delegate
        delegate.serialDidDisconnect(peripheral, error: error as NSError?)
        NotificationCenter.default.post(name: .BluetoothDidStateChange, object: self)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("didFailToConnect:\(peripheral) \(error)")
        pendingPeripheral = nil

        // just send it to the delegate
        delegate.serialDidFailToConnect(peripheral, error: error as NSError?)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        print("centralManagerDidUpdateState:\(central.state.rawValue)")
        
        switch central.state {
        case .unknown:
            print("State:unknown")
        case .resetting:
            print("State:resetting")
        case .unauthorized:
            print("State:unauthorized")
        case .unsupported:
            print("State:unsupported")
        case .poweredOff:
            print("State:poweredOff")
        case .poweredOn:
            print("State:poweredOn")
        }
        
        let status = CBPeripheralManager.authorizationStatus()
        if (status == .notDetermined) {
            print("Status:notDetermined")
        } else if (status == .authorized) {
            print("Status:authorized")
        } else if (status == .denied) {
            print("Status:denied")
        } else if (status == .restricted) {
            print("Status:restricted")
        }

        // note that "didDisconnectPeripheral" won't be called if BLE is turned off while connected
        connectedPeripheral = nil
        pendingPeripheral = nil

        // send it to the delegate
        delegate.serialDidChangeState()
        
        NotificationCenter.default.post(name: .BluetoothDidStateChange, object: self)
    }
    
    
    // MARK: CBPeripheralDelegate functions
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("didDiscoverServices: \(peripheral.services) \(error)")
        // discover the 0xFFE1 characteristic for all services (though there should only be one)
        for service in peripheral.services! {
            print("didDiscoverServices: service:\(service)")
            peripheral.discoverCharacteristics([characteristicUUID, testCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("didDiscoverCharacteristicsFor:\(service) \(error)")
        // check whether the characteristic we're looking for (0xFFE1) is present - just to be sure
        for characteristic in service.characteristics! {
            print("didDiscoverCharacteristicsFor: characteristic:\(characteristic)")
            if characteristic.uuid == characteristicUUID
                || characteristic.uuid == testCharacteristicUUID {
                // subscribe to this value (so we'll get notified when there is serial data for us..)
                peripheral.setNotifyValue(true, for: characteristic)
                
                // keep a reference to this characteristic so we can write to it
                writeCharacteristic = characteristic
                
                // find out writeType
                writeType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
                
                // notify the delegate we're ready for communication
                delegate.serialIsReady(peripheral)
                
                print("isReady:\(connectedPeripheral)")
                
                NotificationCenter.default.post(name: .BluetoothDidStateChange, object: self)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
//        print("didUpdateValueFor:\(characteristic) \(error)")
        // notify the delegate in different ways
        // if you don't use one of these, just comment it (for optimum efficiency :])
        let data = characteristic.value
        guard data != nil else { return }
        
        // first the data
        delegate.serialDidReceiveData(data!)
        
        // then the string
        if let str = String(data: data!, encoding: String.Encoding.utf8) {
            delegate.serialDidReceiveString(str)
            let userInfo = [BluetoothDidReceiveStringMessagekey : str]
            NotificationCenter.default.post(name: .BluetoothDidReceiveString,
                                            object: self, userInfo: userInfo)
        } else {
//            print("Received an invalid string!") //uncomment for debugging
        }
        
        // now the bytes array
        var bytes = [UInt8](repeating: 0, count: data!.count / MemoryLayout<UInt8>.size)
        (data! as NSData).getBytes(&bytes, length: data!.count)
        delegate.serialDidReceiveBytes(bytes)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
//        print("didWriteValueFor:\(characteristic) \(error)")
        // notify the delegate in different ways
        // if you don't use one of these, just comment it (for optimum efficiency :])
        let data = characteristic.value
        guard data != nil else { return }
        
        // first the data
        delegate.serialDidSendData(data!)
        
        // then the string
        if let str = String(data: data!, encoding: String.Encoding.utf8) {
            delegate.serialDidSendString(str)
            let userInfo = [BluetoothDidSendStringMessageKey : str]
            NotificationCenter.default.post(name: .BluetoothDidSendString,
                                            object: self, userInfo: userInfo)
        } else {
//                        print("Sent an invalid string!") //uncomment for debugging
        }
        
        // now the bytes array
        var bytes = [UInt8](repeating: 0, count: data!.count / MemoryLayout<UInt8>.size)
        (data! as NSData).getBytes(&bytes, length: data!.count)
        delegate.serialDidSendBytes(bytes)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        print("didReadRSSI:\(RSSI) \(error)")
        delegate.serialDidReadRSSI(RSSI)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("didModifyServices:\(peripheral) \(invalidatedServices)")
        disconnect()
    }
}
