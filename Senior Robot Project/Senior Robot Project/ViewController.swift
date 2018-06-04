//
//  ViewController.swift
//  Senior Robot Project
//
//  Created by Kazi tasnim on 5/21/18.
//  Copyright © 2018 Kazi Tasnim. All rights reserved.
//

import Foundation
import UIKit
import CoreBluetooth
import CoreMotion

var txCharacteristic : CBCharacteristic?
var rxCharacteristic : CBCharacteristic?
var blePeripheral : CBPeripheral?
var characteristicASCIIValue = NSString()

let halfPi = Double.pi / 2

class BLECentralViewController : UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var batteryLabel: UILabel!
    
    //Data
    var centralManager : CBCentralManager!
    var RSSIs = [NSNumber]()
    var peripherals: [CBPeripheral] = []
    var characteristicValue = [CBUUID: NSData]()
    var timer = Timer()
    var characteristics = [String : CBCharacteristic]()
    var motion = CMMotionManager()
    var isDriving = false
    var isSpinning = false
    var battery = ""
    
    enum DrivingState {
        case connecting
        case failed
        case driving
        case spinning
        case stopped
    }
    
    var buttonState = DrivingState.connecting
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        print("init")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        disconnectFromDevice()
        super.viewDidAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("Stopping")
        centralManager?.stopScan()
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }
    
    func writeInteger(val: UInt8) {
        if let blePeripheral = blePeripheral {
            if let txCharacteristic = txCharacteristic {
                var num = val
                let data = NSData(bytes: &num, length: 1)
                blePeripheral.writeValue(data as Data, for: txCharacteristic, type: CBCharacteristicWriteType.withResponse)
            } else {
                print("Cannot transmit to connected device!")
            }
        } else {
            print("No device to transmit to")
        }
    }
    
    func writeDrivingDirections(cmd: String, left: UInt8, right: UInt8) {
        if let blePeripheral = blePeripheral {
            if let txCharacteristic = txCharacteristic {
                var data: [UInt8] = Array(repeating: 0, count: 8)
                let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: 1)
                ptr.initialize(from: cmd, count: 1)
                (cmd as NSString).getCString(ptr, maxLength: 1, encoding: String.Encoding.utf8.rawValue)
                data[0] = UInt8.init(ptr.pointee)
                data[1] = left
                data[2] = right
                print("writing: \(data)")
                blePeripheral.writeValue(Data.init(bytes: data), for: txCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
            }
        }
    }
    
    func writeString(val: String) {
        var data: [UInt8] = Array(repeating: 0, count: 8)
        let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: 1)
        ptr.initialize(from: val, count: 1)
        (val as NSString).getCString(ptr, maxLength: 1, encoding: String.Encoding.utf8.rawValue)
        data[0] = UInt8.init(ptr.pointee)
        //let str = (val as NSString).data(using: String.Encoding.utf8.rawValue)
        if let blePeripheral = blePeripheral {
            if let txCharacteristic = txCharacteristic {
                print("writing string: \(data)")
                blePeripheral.writeValue(Data.init(bytes: data), for: txCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
                //blePeripheral.writeValue(str!, for: txCharacteristic, type: CBCharacteristicWriteType.withoutResponse)
            }
        } else {
            print("No device to transmit to")
        }
    }

    /*Okay, now that we have our CBCentalManager up and running, it's time to start searching for devices. You can do this by calling the "scanForPeripherals" method.*/
    
    func startScan() {
        peripherals = []
        print("Now Scanning...")
        self.timer.invalidate()
        centralManager?.scanForPeripherals(withServices: [BLEService_UUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey:false])
        Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(self.cancelScan), userInfo: nil, repeats: false)
    }
    
    /*We also need to stop scanning at some point so we'll also create a function that calls "stopScan"*/
    @objc func cancelScan() {
        self.centralManager?.stopScan()
        print("Scan Stopped")
        print("Number of Peripherals Found: \(peripherals.count)")
        
        print("stopped scan with \(peripherals.count) peripherals found")
        if (peripherals.count > 0) {
            blePeripheral = peripherals[0]
            connectToDevice()
            
            print("connecting to first device found")
            button.setTitleColor(UIColor.green, for: .normal)
            button.setTitle("Start driving", for: .normal)
            buttonState = DrivingState.stopped
            
        } else {
            button.setTitleColor(UIColor.orange, for: .normal)
            button.setTitle("Retry to connect", for: .normal)
            buttonState = DrivingState.failed
        }
    }
    
    //-Terminate all Peripheral Connection
    /*
     Call this when things either go wrong, or you're done with the connection.
     This cancels any subscriptions if there are any, or straight disconnects if not.
     (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
     */
    func disconnectFromDevice () {
        if blePeripheral != nil {
            // We have a connection to the device but we are not subscribed to the Transfer Characteristic for some reason.
            // Therefore, we will just disconnect from the peripheral
            centralManager?.cancelPeripheralConnection(blePeripheral!)
        }
    }
    
    
    func restoreCentralManager() {
        //Restores Central Manager delegate if something went wrong
        centralManager?.delegate = self
    }
    
    
    /*
     Called when the central manager discovers a peripheral while scanning. Also, once peripheral is connected, cancel scanning.
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        blePeripheral = peripheral
        self.peripherals.append(peripheral)
        self.RSSIs.append(RSSI)
        peripheral.delegate = self
        if blePeripheral == nil {
            print("Found new pheripheral devices with services")
            print("Peripheral name: \(String(describing: peripheral.name))")
            print("**********************************")
            print ("Advertisement Data : \(advertisementData)")
        }
    }
    
    //Peripheral Connections: Connecting, Connected, Disconnected
    
    //-Connection
    func connectToDevice () {
        centralManager?.connect(blePeripheral!, options: nil)
    }
    
    /*
     Invoked when a connection is successfully created with a peripheral.
     This method is invoked when a call to connect(_:options:) is successful. You typically implement this method to set the peripheral’s delegate and to discover its services.
     */
    //-Connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("*****************************")
        print("Connection complete")
        print("Peripheral info: \(String(describing: blePeripheral))")
        
        //Stop Scan- We don't need to scan once we've connected to a peripheral. We got what we came for.
        centralManager?.stopScan()
        print("Scan Stopped")
        
        //Discovery callback
        peripheral.delegate = self
        //Only look for services that matches transmit uuid
        peripheral.discoverServices([BLEService_UUID])
        print("Finish connecting")
    }

    /*
     Invoked when the central manager fails to create a connection with a peripheral.
     */
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if error != nil {
            print("Failed to connect to peripheral")
            return
        }
    }
    
    func disconnectAllConnection() {
        centralManager.cancelPeripheralConnection(blePeripheral!)
    }
    
    /*
     Invoked when you discover the peripheral’s available services.
     This method is invoked when your app calls the discoverServices(_:) method. If the services of the peripheral are successfully discovered, you can access them through the peripheral’s services property. If successful, the error parameter is nil. If unsuccessful, the error parameter returns the cause of the failure.
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("*******************************************************")
        
        if ((error) != nil) {
            print("Error discovering services: \(error!.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            return
        }
        //We need to discover the all characteristic
        for service in services {
            
            peripheral.discoverCharacteristics(nil, for: service)
            // bleService = service
        }
        print("Discovered Services: \(services)")
    }
    
    /*
     Invoked when you discover the characteristics of a specified service.
     This method is invoked when your app calls the discoverCharacteristics(_:for:) method. If the characteristics of the specified service are successfully discovered, you can access them through the service's characteristics property. If successful, the error parameter is nil. If unsuccessful, the error parameter returns the cause of the failure.
     */
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        print("*******************************************************")
        
        if ((error) != nil) {
            print("Error discovering services: \(error!.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        print("Found \(characteristics.count) characteristics!")
        
        for characteristic in characteristics {
            //looks for the right characteristic
            
            if characteristic.uuid.isEqual(BLE_Characteristic_uuid_Rx)  {
                rxCharacteristic = characteristic
                
                //Once found, subscribe to the this particular characteristic...
                peripheral.setNotifyValue(true, for: rxCharacteristic!)
                // We can return after calling CBPeripheral.setNotifyValue because CBPeripheralDelegate's
                // didUpdateNotificationStateForCharacteristic method will be called automatically
                peripheral.readValue(for: characteristic)
                print("Rx Characteristic: \(characteristic.uuid)")
            }
            if characteristic.uuid.isEqual(BLE_Characteristic_uuid_Tx){
                txCharacteristic = characteristic
                print("Tx Characteristic: \(characteristic.uuid)")
            }
            peripheral.discoverDescriptors(for: characteristic)
        }
    }
    
    // Getting Values From Characteristic
    
    /*After you've found a characteristic of a service that you are interested in, you can read the characteristic's value by calling the peripheral "readValueForCharacteristic" method within the "didDiscoverCharacteristicsFor service" delegate.
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if characteristic == rxCharacteristic {
            if let ASCIIstring = NSString(data: characteristic.value!, encoding: String.Encoding.utf8.rawValue) {
                characteristicASCIIValue = ASCIIstring
                let val = characteristicASCIIValue as String
                print("Value Recieved: \(val)")
                NotificationCenter.default.post(name:NSNotification.Name(rawValue: "Notify"), object: nil)
                if battery.count < 8 {
                    battery.append(val)
                }
                
                if battery.count >= 8 {
                    // only keep first eight characters, if more came in
                    if battery.count > 8 {
                        battery = String(Array(battery)[0..<8])
                    }
                    print("Got battery reading: \(battery)")
                    if let batt = Double(battery) {
                        // round to 3 digits precision
                        let num = Double(round(1000 * batt) / 1000)
                        batteryLabel.text = "Battery level: \(num)"
                        if let batt = Float.init(battery) {
                            if (batt > 4) {
                                batteryLabel.textColor = UIColor.green
                            } else if (batt > 3) {
                                batteryLabel.textColor = UIColor.yellow
                            } else {
                                batteryLabel.textColor = UIColor.red
                            }
                        }
                    } else {
                        print("Couldn't parse battery reading \(battery)")
                    }
                }
            }
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        print("*******************************************************")
        
        if error != nil {
            print("\(error.debugDescription)")
            return
        }
        if ((characteristic.descriptors) != nil) {
            
            for x in characteristic.descriptors!{
                let descript = x as CBDescriptor?
                print("function name: DidDiscoverDescriptorForChar \(String(describing: descript?.description))")
                print("Rx Value \(String(describing: rxCharacteristic?.value))")
                print("Tx Value \(String(describing: txCharacteristic?.value))")
            }

            startAccelerometers()
            pollBattery()
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("*******************************************************")
        
        if (error != nil) {
            print("Error changing notification state:\(String(describing: error?.localizedDescription))")
            
        } else {
            print("Characteristic's value subscribed")
        }
        
        if (characteristic.isNotifying) {
            print ("Subscribed. Notification has begun for: \(characteristic.uuid)")
        }
    }
    
    
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected")
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error discovering services: error")
            return
        }
        print("Message sent")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        guard error == nil else {
            print("Error discovering services: error")
            return
        }
        print("Succeeded!")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard error == nil else {
            print("Error updating value: \(error)")
            return
        }
        print("Updated descriptor value: \(descriptor.value)")
    }
    
    
    /*
     Invoked when the central manager’s state is updated.
     This is where we kick off the scan if Bluetooth is turned on.
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == CBManagerState.poweredOn {
            // We will just handle it the easy way here: if Bluetooth is on, proceed...start scan!
            print("Bluetooth Enabled")
            startScan()
        } else {
            //If Bluetooth is off, display a UI alert message saying "Bluetooth is not enable" and "Make sure that your bluetooth is turned on"
            print("Bluetooth Disabled- Make sure your Bluetooth is turned on")
            
            let alertVC = UIAlertController(title: "Bluetooth is not enabled", message: "Make sure that your bluetooth is turned on", preferredStyle: UIAlertControllerStyle.alert)
            let action = UIAlertAction(title: "ok", style: UIAlertActionStyle.default, handler: { (action: UIAlertAction) -> Void in
                self.dismiss(animated: true, completion: nil)
            })
            alertVC.addAction(action)
            self.present(alertVC, animated: true, completion: nil)
        }
    }
    
    func pollBattery() {
        // make initial request immediately
        self.writeString(val: "b")
        self.battery = "" // read the response into this string
        
        // schedule updates
        Timer.scheduledTimer(withTimeInterval: (15), repeats: true, block: { (timer) in
            print("requesting battery status")
            // request battery status
            self.battery = ""
            self.writeString(val: "b")
        })
    }
    
    func startAccelerometers() {
        // Make sure the accelerometer hardware is available.
        if self.motion.isAccelerometerAvailable {
            self.motion.accelerometerUpdateInterval = 45.0 / 60.0  // 60 Hz
            self.motion.startDeviceMotionUpdates()
            print("start accelerometers")
        
            self.timer.invalidate()
            self.timer = Timer(fire: Date(), interval: (1), repeats: true, block: { (timer) in
                if let data = self.motion.deviceMotion {
                    // atan2(x, y) is roughly the same as data.attitude.roll
                    let gravity = data.gravity
                    let forwards = gravity.z < 0
                    print("forwards? \(forwards)")
                    print("x \(gravity.x) y \(gravity.y) z \(gravity.z)")
                    self.setWheelsfromAccel(x: gravity.x, y: gravity.y, forwards: forwards)
                }
            })
            
            // Add the timer to the current run loop.
            RunLoop.current.add(self.timer, forMode: .defaultRunLoopMode)
        }
    }
    
    func stopDriving() {
        print("stop")
        writeString(val: "s")
        button.setTitleColor(.green, for: .normal)
        button.setTitle("Start driving", for: UIControlState.normal)
        buttonState = DrivingState.stopped
        isDriving = false
    }
    
    func spin(direction: String) {
        print("spin")
        stopDriving()
        if !isSpinning {
            buttonState = DrivingState.spinning
            writeString(val: direction)
            button.setTitle("Stop", for: .normal)
            button.setTitleColor(.red, for: .normal)
        }
        
        isSpinning = !isSpinning
    }
    
    @IBAction func spinRight(_ sender: UIButton) {
        spin(direction: "y")
    }
    
    @IBAction func spinLeft(_ sender: UIButton) {
        spin(direction: "z")
    }
    
    @IBAction func clickStartStop(_ sender: UIButton) {
        if isDriving {
            // stop driving
            stopDriving()
        } else if isSpinning {
            // stop spinning
            stopDriving()
        } else if (buttonState == DrivingState.failed) {
            // restart scanning for bluetooth
            startScan()
            buttonState = DrivingState.connecting
            button.setTitle("Connecting...", for: .normal)
            button.setTitleColor(UIColor.gray, for: .normal)
            isDriving = false
        } else if (buttonState == DrivingState.stopped) {
            print("go")
            // start driving
            sender.setTitleColor(.red, for: .normal)
            sender.setTitle("Stop", for: UIControlState.normal)
            buttonState = DrivingState.driving
            isDriving = true
        }
        isSpinning = false
    }
    
    static func mapRange(a1: Double, a2: Double, b1: Double, b2: Double, s: Double) -> Double {
        return (b1 + ((s - a1)*(b2 - b1))/(a2 - a1))
    }
  
        
    func setWheelsfromAccel (x: Double, y: Double, forwards: Bool) {
        var rightSpeed = 0.0
        var leftSpeed = 0.0
        
        // max speed is half of what m3pi can do, for more gradual ramp
        let speed = BLECentralViewController.mapRange(a1: -1, a2: 1, b1: 0, b2: 128, s: x)
        rightSpeed = speed
        leftSpeed = speed

        if (y > 0) {
            leftSpeed += leftSpeed * y
            rightSpeed += rightSpeed * (y / 2)
        } else {
            rightSpeed -= rightSpeed * y
            leftSpeed -= leftSpeed * (y / 2)
        }
        
        if leftSpeed < 0 {
            leftSpeed = 0
            print("negative left speed: \(leftSpeed)")
            return
        } else if leftSpeed >= 255 {
            leftSpeed = 255
            print("excessive left speed: \(leftSpeed)")
            return
        }
        
        if rightSpeed < 0 {
            rightSpeed = 0
            print("negative right speed: \(rightSpeed)")
            return
        } else if rightSpeed >= 255 {
            rightSpeed = 255
            print("excessive right speed: \(rightSpeed)")
            return
        }
       
        var cmd = "f"
        if forwards {
            print("forward speed: \(speed) \(rightSpeed) \(leftSpeed)")
        } else{
            print("reverse speed: \(speed) \(rightSpeed) \(leftSpeed)")
            cmd = "r"
        }
        
        if isDriving {
            writeDrivingDirections(cmd: cmd, left: UInt8.init(leftSpeed), right: UInt8.init(rightSpeed))
        }
}
    

}

