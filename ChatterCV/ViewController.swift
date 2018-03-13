//
//  ViewController.swift
//  ChatterCV
//
//  Created by Kendall Lui on 2/5/18.
//  Copyright © 2018 ARMS Reserach Laboratory. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, CVChatterProcessorDelegate {
    
    let captureSession = AVCaptureSession()
    let chatterProcessor = CVChatterProcessor()
    
    var backCamera:AVCaptureDevice?
    var frontCamera:AVCaptureDevice?
    var videoPreviewLayer:AVCaptureVideoPreviewLayer?
    var videoOutput = AVCaptureVideoDataOutput()
    var centerPixelRow = [[UInt8]]()
    var pixelX = [Double]()
    
    
    //@IBOutlet weak var cameraPreview: UIView!
    @IBOutlet weak var cameraPostview: UIImageView!
    @IBOutlet weak var IntensityPlot: GraphView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        chatterProcessor.delegate = self
        captureSession.sessionPreset = AVCaptureSessionPresetPhoto
        
        if let deviceDiscoverSession = AVCaptureDeviceDiscoverySession(deviceTypes: [AVCaptureDeviceType.builtInWideAngleCamera], mediaType: AVMediaTypeVideo, position: AVCaptureDevicePosition.unspecified)
        {
            for device in deviceDiscoverSession.devices {
                if(device.position == AVCaptureDevicePosition.back) {
                    backCamera = device
                    if (backCamera?.hasTorch)! {
                        do {
                            try backCamera?.lockForConfiguration()
                            if (backCamera?.torchMode == AVCaptureTorchMode.on) {
                                backCamera?.torchMode = AVCaptureTorchMode.off
                            } else {
                                do {
                                    try backCamera?.setTorchModeOnWithLevel(0.0001)
                                } catch {
                                    print(error)
                                }
                            }
                            backCamera?.unlockForConfiguration()
                        } catch {
                            print(error)
                        }
                    }
                    
                } else {
                    frontCamera = device
                }
            }
        }
        
        if (backCamera != nil)
        {
            do {
                let input = try AVCaptureDeviceInput(device: backCamera)
                captureSession.addInput(input)
            } catch {
                print(error)
            }
        }
        
        //Apply Preview
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        videoPreviewLayer?.frame = cameraPostview.bounds
        
        //        cameraPreview.layer.addSublayer(videoPreviewLayer!)
        
        
        //Setup Data Output Camera
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as
            AnyHashable: Int(kCVPixelFormatType_32BGRA)]
        let sessionQueue = DispatchQueue(label: "VideoQueue",
                                         attributes: [], target: nil)
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            let connection = videoOutput.connection(withMediaType: AVFoundation.AVMediaTypeVideo)
            connection?.videoOrientation = .portrait
        } else {
            print("Could not add video data as output.")
        }
        captureSession.startRunning()
        
        
        
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bitsPerComponent = 8
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)!
        let byteBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Make a center line blue
        for j in (height/2)-10..<(height/2)+10 {
            for i in 0..<width {
                let index = (j * width + i) * 4
                
                byteBuffer[index+1] = UInt8(255)// G
                
                /*
                 let b = byteBuffer[index]
                 let g = byteBuffer[index+1]
                 let r = byteBuffer[index+2]
                 //let a = byteBuffer[index+3]
                 
                 if r > UInt8(128) && g < UInt8(128) {
                 byteBuffer[index] = UInt8(255)
                 byteBuffer[index+1] = UInt8(0)
                 byteBuffer[index+2] = UInt8(0)
                 } else {
                 byteBuffer[index] = g
                 byteBuffer[index+1] = r
                 byteBuffer[index+2] = b
                 }
                 */
            }
        }
        
        
        centerPixelRow = []
        pixelX = []
        let j = height/2
        for i in 0..<width {
            let index = (j * width + i) * 4
            centerPixelRow.append([byteBuffer[index],byteBuffer[index+1],byteBuffer[index+2]])
            pixelX.append(Double(i))
        }
        
        chatterProcessor.RGBPixels = centerPixelRow
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let newContext = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        self.cameraPostview.clipsToBounds = true;
        self.cameraPostview.contentMode = .scaleAspectFill
        if let context = newContext {
            let cameraFrame = context.makeImage()
            
            DispatchQueue.main.async {
                self.cameraPostview.image = UIImage(cgImage: cameraFrame!)
            }
        }
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
    }
    
    @IBAction func captureIntensity(_ sender: Any) {
        
        let intensity = stride(from: 0, to: (self.chatterProcessor.greyIntensity.count), by:1).map{
            Double((self.chatterProcessor.greyIntensity[$0]))
        }
        let count = IntensityPlot.addPlot(pixelX, y_coors: intensity, color: (0,255,0))
        if(count > 0)
        {
            IntensityPlot.removePlot(count-1)
        }
        chatterProcessor.calculateFrequencies()
    }
    
    func fftCalculated() {
        print("GREY: ")
        print(chatterProcessor.greyIntensity)
        let indexMax = chatterProcessor.amplitudes.index(of: chatterProcessor.amplitudes.max()!)!;
        let maxAmpFreq = chatterProcessor.frequencies.remove(at: indexMax);
        print(chatterProcessor.amplitudes[indexMax])
        print(maxAmpFreq)
    }
    
    
}

