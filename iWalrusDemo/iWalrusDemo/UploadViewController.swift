//
//  ViewController.swift
//  iWalrusDemo
//
//  Created by Shahnawaz Akhtar on 06/07/25.
//

import UIKit
import WalrusSDK

class UploadViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    let walrusClient = WalrusManager.shared.client
    @IBOutlet weak var blobID: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func uploadButtonTapped(_ sender: UIButton) {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        present(imagePicker, animated: true, completion: nil)
    }
    

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)

        if let image = info[.originalImage] as? UIImage,
           let imageData = image.jpegData(compressionQuality: 0.2) {
            Task {
                await uploadImageData(imageData)
            }
        }
    }


    func uploadImageData(_ data: Data) async {
        do{// Here you'd call your iWalrus SDK upload function
            self.blobID.text = "Awaiting response.."
            let response = try await walrusClient.putBlob(data: data)
            if let blobId = findBlobId(in: response) {
                self.blobID.text = "BLOB ID:  \(blobId)"
            } else {
                self.blobID.text = "\(response)"
            }
        } catch {
            self.blobID.text = "\(error)"
        }
       }

       // Handle cancel
       func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
           picker.dismiss(animated: true, completion: nil)
       }
    
    func findBlobId(in json: Any) -> String? {
        if let dict = json as? [String: Any] {
            for (key, value) in dict {
                if key == "blobId", let blobId = value as? String {
                    return blobId
                }
                // Recursively search nested dictionaries or arrays
                if let found = findBlobId(in: value) {
                    return found
                }
            }
        } else if let array = json as? [Any] {
            for item in array {
                if let found = findBlobId(in: item) {
                    return found
                }
            }
        }
        return nil
    }


}

