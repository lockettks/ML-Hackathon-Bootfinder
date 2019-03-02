//
//  MainViewController.swift
//  ImageSimilarities
//
//  Created by Wess Cope on 12/17/18.
//  Copyright © 2018 Skafos. All rights reserved.
//

import Foundation
import UIKit
import Skafos
import CoreML
import Vision
import SnapKit

class MainViewController : ViewController {
    // This will be the asset name you use in drag and drop on the dashboard
    private let assetName:String                  = "ImageSimilarity"
    private let imageSimilarity:ImageSimilarity!  = ImageSimilarity()
    var referenceRankingTest = ""
    
    private var currentImage:UIImage!             = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.photoButton.addTarget(self, action: #selector(photoAction(_:)), for: .touchUpInside)
        self.cameraButton.addTarget(self, action: #selector(cameraAction(_:)), for: .touchUpInside)
        
        // Load Model From Download Cache
        Skafos.load(asset: self.assetName) { (error, asset) in
            guard let model = asset.model else {
                debugPrint("No model available")
                return
            }
            self.imageSimilarity.model = model
        }
        
        // Receive Notification When New Model Has Been Downloaded And Compiled
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(MainViewController.reloadModel(_:)),
                                               name: Skafos.Notifications.assetUpdateNotification(assetName),
                                               object: nil)
    }
    
    @objc func reloadModel(_ notification:Notification) {
        debugPrint("Model Reloaded")
        Skafos.load(asset: self.assetName) { (error, asset) in
            guard let model = asset.model else {
                debugPrint("No model available")
                return
            }
            self.imageSimilarity.model = model
           print("================== MODEL RELOADED! ==================")
        }
    }
    
    @objc
    func cameraAction(_ sender:Any? = nil) {
        let myPickerController = UIImagePickerController()
        myPickerController.delegate = self;
        myPickerController.sourceType = .camera
        self.present(myPickerController, animated: true, completion: nil)
    }
    
    @objc
    func photoAction(_ sender:Any? = nil) {
        let myPickerController = UIImagePickerController()
        myPickerController.delegate = self;
        myPickerController.sourceType = .photoLibrary
        self.present(myPickerController, animated: true, completion: nil)
    }

        func similarifyImage(image:UIImage) {
            self.currentImage = image
            let orientation   = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue))!
            guard let ciImage = CIImage(image: image) else { fatalError("Bad image") }
            
            
            let model = try! VNCoreMLModel(for: self.imageSimilarity.model)
    
            let request = VNCoreMLRequest(model: model) {[weak self] request, error in
                self?.processQuery(for: request, error: error)
            }
            request.imageCropAndScaleOption = .centerCrop
            
            
    
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
    
                do {
                    try handler.perform([request])
                } catch {
                    print("Failed: \n\(error.localizedDescription)")
                }
            }
        }
    
    
    lazy var similarityRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: self.imageSimilarity.model)
            
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processQuery(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    func processQuery(for request: VNRequest, error: Error?, k: Int = 5) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                self.referenceRankingTest = "Unable to rank image.\n\(error!.localizedDescription)"
                print (self.referenceRankingTest)
                return
            }
            
            let queryResults = results as! [VNCoreMLFeatureValueObservation]
            let distances = queryResults.first!.featureValue.multiArrayValue!
            
            // Create an array of distances to sort
            let numReferenceImages = distances.shape[0].intValue
            var distanceArray = [Double]()
            for r in 0..<numReferenceImages {
                distanceArray.append(Double(distances[r]))
            }
            
            let sorted = distanceArray.enumerated().sorted(by: {$0.element < $1.element})
            let knn = sorted[..<min(k, numReferenceImages)]
            
            var message = "Results\n\n"
            knn.forEach {
                let result = "Element: \($0.element)  Offset: \($0.offset)\n"
                message.append(result)
            }
            print (message)
            self.showSimilarities(message: message)
        }
    }
    
    func showSimilarities(message:String) {
        let alertController = UIAlertController(title: "Similarities", message: message, preferredStyle: .alert)
        let previewImage = self.currentImage.imageWithSize(scaledToSize: CGSize(width: 150, height: 150))
        let customView = UIImageView(image: previewImage)
        alertController.view.addSubview(customView)
        
        customView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(100)
            make.centerX.equalToSuperview()
            make.height.equalTo(previewImage.size.height)
        }
        
        alertController.view.snp.makeConstraints { (make) in
            make.height.equalTo(customView.frame.height+190)
        }
        
        let action = UIAlertAction(title: "OK", style: .default) { (actionitem) in
            if let imagePicker = (self.presentedViewController as? UIImagePickerController) {
                if (imagePicker.sourceType == .camera) {
                    self.dismiss(animated: false, completion: nil)
                }
            }
        }
        
        alertController.addAction(action)
        
        // Save to Photo Library
        if let imagePicker = (self.presentedViewController as? UIImagePickerController) {
            if (imagePicker.sourceType == .camera) {
                let saveAction = UIAlertAction(title: "Save Image", style: .default) { (actionitem) in
                    UIImageWriteToSavedPhotosAlbum(self.currentImage, nil, nil, nil)
                    self.dismiss(animated: false, completion: nil)
                }
                alertController.addAction(saveAction)
            }
        }
        
        self.presentedViewController?.present(alertController, animated: true, completion: nil)
    }

}

extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate{
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            self.similarifyImage(image: image)
        }else{
            print("Something went wrong")
            self.dismiss(animated: true, completion: nil)
        }
    }
}
