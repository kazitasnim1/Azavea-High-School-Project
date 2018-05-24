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



class BLECentralViewController : UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    //Data
    var centralManager : CBCentralManager!
    var RSSIs = [NSNumber]()
    var data = NSMutableData()
    var writeData: String = ""
    var peripherals: [CBPeripheral] = []
    var characteristicValue = [CBUUID: NSData]()
    var timer = Timer()
    var characteristics = [String : CBCharacteristic]()
    var motion = CMMotionManager()
    var isDriving = false
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
       super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        loadViewIfNeeded();
        print("init1")
        startAccelerometers()
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        print("init2")
    }
    
    
    @IBAction func refreshAction(_ sender: AnyObject) {
        disconnectFromDevice()
        self.peripherals = []
        self.RSSIs = []
        startScan()
    }
    
    override func viewDidLoad() {
        print("viewDidLoad")
        super.viewDidLoad()
        
        /*Our key player in this app will be our CBCentralManager. CBCentralManager objects are used to manage discovered or connected remote peripheral devices (represented by CBPeripheral objects), including scanning for, discovering, and connecting to advertising peripherals.
         */
        centralManager = CBCentralManager(delegate: self, queue: nil)
        let backButton = UIBarButtonItem(title: "Disconnect", style: .plain, target: nil, action: nil)
        navigationItem.backBarButtonItem = backButton
    }
    
    override func viewDidAppear(_ animated: Bool) {
        print("view appeared")
        disconnectFromDevice()
        super.viewDidAppear(animated)
        print("View Cleared")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("Stop Scanning")
        centralManager?.stopScan()
    }
    
    func writeInteger(val:UInt8) {
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
    
    func writeString(val: String) {
        print(val)
        let str = (val as NSString).data(using: String.Encoding.utf8.rawValue)
        if let blePeripheral = blePeripheral {
            if let txCharacteristic = txCharacteristic {
                blePeripheral.writeValue(str!, for: txCharacteristic, type: CBCharacteristicWriteType.withResponse)
            }
        } else {
            print("No device to transmit to")
        }
    }
    
    func testDrive() {
        writeString(val: "b")
        //writeString(val: "5")
        //writeString(val: "5")
        //writeInteger(val: 5)
        //writeInteger(val: 5)
    }
    
    /*Okay, now that we have our CBCentalManager up and running, it's time to start searching for devices. You can do this by calling the "scanForPeripherals" method.*/
    
    func startScan() {
        peripherals = []
        print("Now Scanning...")
        self.timer.invalidate()
        centralManager?.scanForPeripherals(withServices: [BLEService_UUID] , options: [CBCentralManagerScanOptionAllowDuplicatesKey:false])
        Timer.scheduledTimer(timeInterval: 7, target: self, selector: #selector(self.cancelScan), userInfo: nil, repeats: false)
    }
    
    /*We also need to stop scanning at some point so we'll also create a function that calls "stopScan"*/
    @objc func cancelScan() {
        self.centralManager?.stopScan()
        print("Scan Stopped")
        print("Number of Peripherals Found: \(peripherals.count)")
        
        if (peripherals.count > 1) {
            print("Found more than one peripheral! All are:")
            for peripheral in peripherals {
                print("\(peripheral.name)")
            }
        }
        
        if (peripherals.count > 0) {
            print("Found peripheral; connecting...")
            blePeripheral = peripherals[0]
            print("\(blePeripheral?.name)")
            connectToDevice()
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
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
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
        
        //Erase data that we might have
        data.length = 0
        
        //Discovery callback
        peripheral.delegate = self
        //Only look for services that matches transmit uuid
        peripheral.discoverServices([BLEService_UUID])
        print("Finish connecting")
     /*
        //Once connected, move to new view controller to manager incoming and outgoing data
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        let uartViewController = storyboard.instantiateViewController(withIdentifier: "UartModuleViewController") as! UartModuleViewController
        
        uartViewController.peripheral = peripheral
        
        navigationController?.pushViewController(uartViewController, animated: true)
    */
        
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
                print("Value Recieved: \((characteristicASCIIValue as String))")
                NotificationCenter.default.post(name:NSNotification.Name(rawValue: "Notify"), object: nil)
                
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
            
            // TODO: here? elsewhere?
            
            startAccelerometers()
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
    func startAccelerometers() {
        // Make sure the accelerometer hardware is available.
        if self.motion.isAccelerometerAvailable {
            self.motion.accelerometerUpdateInterval = 45.0 / 60.0  // 60 Hz
            self.motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
            print("start accelerometers")
            // Configure a timer to fetch the data.
        
             self.timer = Timer(fire: Date(), interval: (45.0/60.0),
                               repeats: true, block: { (timer) in
                                if let data = self.motion.deviceMotion {
                                    let yaw = data.attitude.yaw
                                    let roll = data.attitude.roll
                                    let pitch = data.attitude.pitch
                                    self.setWheelsfromAccel(p: pitch, r: roll, y: yaw)
                                    print("values: \(yaw) \(roll)")
                                }
                             /*   // Get the accelerometer data.
                                if let data = self.motion.accelerometerData {
                                    let x = data.acceleration.x
                                    let y = data.acceleration.y
                                    let z = data.acceleration.z
                                    print("got a reading: \(x) \(y) \(z)")
                                    setWheelsfromAccel(p: <#T##Double#>, r: <#T##Double#>)
                                    // Use the accelerometer data in your app.
                                }*/
            })
            
            // Add the timer to the current run loop.
            RunLoop.current.add(self.timer, forMode: .defaultRunLoopMode)
        }
    }
    
    
    @IBAction func clickStartStop(_ sender: UIButton) {    
        print("it worked")
        if isDriving {
            print("stop")
            writeString(val: "s")
            sender.setTitle("drive", for: UIControlState.normal)
        }else {
            print("go")
            sender.setTitle("Stop", for: UIControlState.normal)
        }
        isDriving = !isDriving
    }
    
    func mapRange(a1: Double, a2: Double, b1: Double, b2: Double, s: Double) -> UInt8 {
        return (UInt8(b1 + ((s - a1)*(b2 - b1))/(a2 - a1)))
    
    }
  
        
    func setWheelsfromAccel (p: Double, r: Double, y: Double){
        print("setWheelsfromAccel")
        var rightSpeed: UInt8 = 0
        var leftSpeed: UInt8 = 0
      

        var posPitch = false
        var posRoll = false
        
        if (p > 0) {
            posPitch = true;
        }
        print("pitchValues")
        if (r > 0) {
            posRoll = true
        }
        print("rollValues")
        let pitch = p
        let roll = r
        let yaw = y
        rightSpeed = mapRange(a1: 0, a2: Double.pi, b1: 0, b2: 255, s: abs(roll))
            print("rightSpeed: \(rightSpeed)")
        leftSpeed = rightSpeed
        let pitchPct = mapRange(a1: -Double.pi, a2: Double.pi, b1: 0, b2: 1, s: pitch)
            print("pitch: \(pitchPct)")
            print("roll: \(roll)")
            print("yaw: \(yaw)")
       
        
        if (posPitch) {
            leftSpeed -= leftSpeed * UInt8.init(pitchPct)
        } else {
            rightSpeed -= rightSpeed * UInt8.init(pitchPct)
        }
        
        
        if isDriving {
            if posRoll {
                print("Speed: \(rightSpeed) \(leftSpeed)")
               writeString(val: "v")
                
            } else{
                writeString(val: "u")
               /* print("have no pos roll") */
                print("backwardsSpeed: \(rightSpeed) \(leftSpeed)")
                writeInteger(val: rightSpeed)
                writeInteger(val: leftSpeed)
            }
            
        }
       
}
    

}

