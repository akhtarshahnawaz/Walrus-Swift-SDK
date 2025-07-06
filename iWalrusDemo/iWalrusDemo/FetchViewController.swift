//
//  ViewController.swift
//  iWalrusDemo
//
//  Created by Shahnawaz Akhtar on 06/07/25.
//

import UIKit

class FetchViewController: UIViewController {

    let walrusClient = WalrusManager.shared.client
    @IBOutlet weak var BlobID: UITextField!
    @IBOutlet weak var FetchedBlob: UIImageView!
    @IBOutlet weak var tempTest: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }


    @IBAction func fetchBlob(_ sender: UIButton) {
        guard let blobId = BlobID.text, !blobId.isEmpty else { return }

        self.tempTest.text = "Fetching Content.."

        Task {
            do {
                let response = try await walrusClient.getBlobByObjectId(objectId: blobId)
                
                // Assuming the response contains image data, update UI on main thread
                if let image = UIImage(data: response) {
                    self.FetchedBlob.image = image
                    self.tempTest.text = "."
                } else {
                    self.tempTest.text = "Failed to load image from blob data."
                }
            } catch {
                self.tempTest.text = "Error: \(error)"
            }
        }
    }
    
}

