//
//  WATTOApp.swift
//  WATTO
//
//  Created by Matt Gaidica on 4/10/23.
//

import SwiftUI
import CoreBluetooth
import Combine

@main
struct WATTOApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var voltageData: [Float] = Array(repeating: 0.0, count: 200)
    @Published var currentData: [Float] = Array(repeating: 0.0, count: 200)
    @Published var powerData: [Float] = Array(repeating: 0.0, count: 200)
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let serviceUUID = CBUUID(string: "A000")
    private let voltageCharacteristicUUID = CBUUID(string: "A001")
    private let currentCharacteristicUUID = CBUUID(string: "A002")
    private let powerCharacteristicUUID = CBUUID(string: "A003")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            print("Central Manager is not powered on")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral:", error.debugDescription)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                if service.uuid == serviceUUID {
                    peripheral.discoverCharacteristics([voltageCharacteristicUUID, currentCharacteristicUUID, powerCharacteristicUUID], for: service)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value {
            var floatArray: [Float] = []
            let count = data.count / MemoryLayout<Float>.size
            floatArray = [Float](repeating: 0.0, count: count)
            data.withUnsafeBytes { bufferPointer in
                let floatBufferPointer = bufferPointer.bindMemory(to: Float.self)
                floatArray = Array(floatBufferPointer)
            }
            
            DispatchQueue.main.async {
                switch characteristic.uuid {
                case self.voltageCharacteristicUUID:
                    self.updateData(data: &self.voltageData, newData: floatArray)
                case self.currentCharacteristicUUID:
                    self.updateData(data: &self.currentData, newData: floatArray)
                case self.powerCharacteristicUUID:
                    self.updateData(data: &self.powerData, newData: floatArray)
                default:
                    break
                }
            }
        }
    }
    
    private func updateData(data: inout [Float], newData: [Float]) {
        let maxLength = 200
        let overflow = data.count + newData.count - maxLength
        if overflow > 0 {
            data.removeFirst(overflow)
        }
        data.append(contentsOf: newData)
    }
}
