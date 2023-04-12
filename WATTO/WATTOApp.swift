//
//  WATTOApp.swift
//  WATTO
//
//  Created by Matt Gaidica on 4/10/23.
//

import SwiftUI
import CoreBluetooth
import Combine
import Foundation

@main
struct WATTOApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var voltageData: [Float] = Array(repeating: 0.0, count: 1000)
    @Published var currentData: [Float] = Array(repeating: 0.0, count: 1000)
    @Published var powerData: [Float] = Array(repeating: 0.0, count: 1000)
    @Published var doScan: Bool = false
    @Published var debugText: String = ">> Hello, Watto"
    @Published var meanCurrent: Float = 0
    @Published var minCurrent: Float = 0
    @Published var maxCurrent: Float = 0
    @Published var nowCurrent: Float = 0
    @Published var meanPower: Float = 0
    @Published var batteryLife: String = ""
    @Published var currentOffset: Float = 0
    @Published var selectedBatterySize: Int = 40
    let batterySizes = [20, 40, 100, 220, 1000]
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let serviceUUID = CBUUID(string: "A000")
    private let voltageCharacteristicUUID = CBUUID(string: "A001")
    private let currentCharacteristicUUID = CBUUID(string: "A002")
    private let powerCharacteristicUUID = CBUUID(string: "A003")
    
    private var timer1Hz: Timer?
    private var collectionMod: Int = 0
    private var notifyCount: Int = 0
    private let modTable: [Int] = [1, 10, 100]
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        self.batteryLife = formattedBatteryLife(batterySize: self.selectedBatterySize, microAmps: self.meanCurrent)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            timer1Hz = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if self.doScan && self.peripheral == nil {
                    self.centralManager.scanForPeripherals(withServices: [self.serviceUUID], options: nil)
                    self.dprint("Scanning for Watto peripheral")
                }
                if !self.doScan {
                    self.centralManager.stopScan()
                    if let peripheral = self.peripheral {
                        self.centralManager.cancelPeripheralConnection(peripheral)
                        self.dprint("Cancelling scan/connnection")
                    }
                }
                if let _ = self.peripheral {
                    self.meanCurrent = self.currentData.reduce(0, +) / Float(self.currentData.count)
                    self.minCurrent = self.currentData.min() ?? 0
                    self.maxCurrent = self.currentData.max() ?? 0
                    self.nowCurrent = self.currentData.last ?? 0
                    self.meanPower = self.powerData.reduce(0, +) / Float(self.powerData.count) / 1000
                    self.batteryLife = self.formattedBatteryLife(batterySize: self.selectedBatterySize, microAmps: self.meanCurrent)
                }
            }
            
        } else {
            dprint("Central Manager is not powered on")
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
        doScan = false
        dprint("Failed to connect to peripheral: \(error.debugDescription)")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        doScan = false
        dprint("Disconnected from \(peripheral.name ?? "")")
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
                    dprint("Notifying on \(characteristic.uuid)")
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
                    self.notifyCount += 1
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
        if notifyCount % modTable[collectionMod] == 0 {
            let overflow = data.count + newData.count - currentData.count
            if overflow > 0 {
                data.removeFirst(overflow)
            }
            data.append(contentsOf: newData)
        }
    }
    
    func dprint(_ addText: String) {
        print(addText)
        debugText = ">> \(addText)\n\(debugText)"
    }
    
    func computeHistogram(data: [Float], bins: [Float]) -> [Float] {
        let nBins = bins.count
        var histogram = [Float](repeating: 0.0, count: nBins - 1)
        
        for value in data {
            if value != 0.0 && value >= bins.first! && value <= bins.last! {
                for binIndex in 0..<(nBins - 1) {
                    if value >= bins[binIndex] && value < bins[binIndex + 1] {
                        histogram[binIndex] += 1
                        break
                    }
                }
            }
        }
        
        return histogram
    }
    
    func formattedBatteryLife(batterySize: Int, microAmps: Float) -> String {
        var d = 0
        var h = 0
        var m = 0
        if microAmps > 0 {
            let hours = (Float(batterySize) * 1000) / microAmps // battery is mAh
            let totalSeconds = Int(hours * 3600)
            d = totalSeconds / 86400 // Number of days
            h = (totalSeconds % 86400) / 3600 // Remaining hours
            m = (totalSeconds % 3600) / 60 // Remaining minutes
        }
        let dStr = d == 1 ? "\(d) day, " : "\(d) days, "
        let hStr = h == 1 ? "\(h) hour, " : "\(h) hours, "
        let mStr = h == 1 ? "\(m) minute" : "\(m) minutes"
        return dStr + hStr + mStr
    }
    
    func relativeCurrentChange(to: Bool) {
        if to {
            currentOffset = median(of: currentData) ?? 0
        } else {
            currentOffset = 0
        }
    }
    
    func setCollectionMod() {
        collectionMod += 1
        if collectionMod > modTable.count {
            collectionMod = 0
        }
        dprint("(\(collectionMod+1)/\(modTable.count)) Taking every \(modTable[collectionMod])th sample")
    }
    
    func median(of array: [Float]) -> Float? {
        guard !array.isEmpty else { return nil }
        
        let sortedArray = array.sorted()
        let middleIndex = sortedArray.count / 2
        
        if sortedArray.count % 2 == 0 {
            // Even number of elements
            return (sortedArray[middleIndex - 1] + sortedArray[middleIndex]) / 2
        } else {
            // Odd number of elements
            return sortedArray[middleIndex]
        }
    }

    func powerScale(start: Float, end: Float, points: Int, exponent: Float) -> [Float] {
        let step = 1 / Float(points - 1)
        
        var powerScaledValues: [Float] = []
        
        for index in 0...(points - 1) {
            let position = Float(index) * step
            let powerScaledPosition = pow(position, exponent)
            let value = start + (end - start) * powerScaledPosition
            powerScaledValues.append(value)
        }
        
        return powerScaledValues
    }

}
