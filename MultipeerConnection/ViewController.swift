import UIKit
import MultipeerConnectivity

class ViewController: UIViewController, MCSessionDelegate, MCBrowserViewControllerDelegate, MCNearbyServiceAdvertiserDelegate {
    
    @IBOutlet weak var numberLabel: UILabel!
    
    // Image view to display the downloaded image
    @IBOutlet weak var imageView: UIImageView!
    
    var number = 0
    
    var peerID: MCPeerID!
    var mcSession: MCSession!
    var mcAdvertiserAssistant: MCNearbyServiceAdvertiser!
    
    // Progress variable that needs to store the progress of the file transfer
    var fileTransferProgress: Progress?
    
    // Timer that will be used to check the file transfer progress
    var checkProgressTimer: Timer?
    
    // Used by the host to track bytes to receive
    var bytesExpectedToExchange = 0
    
    // Used to track the time taken in transfer, this is for testing purposes.
    // You might get more reliable results using Date to track time
    var transferTimeElapsed = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        peerID = MCPeerID(displayName: UIDevice.current.name)
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
    }

    // MARK: - Buttons Actions
    
    @IBAction func hostButtonAction(_ sender: Any) {
        startHosting()
    }
    
    @IBAction func guestButtonAction(_ sender: Any) {
        joinSession()
    }
    
    @IBAction func sendButtonAction(_ sender: Any) {
        //send data to the other device
        number = number + 1
        sendData(data: "\(number)")
    }
  
    // A new action added to send the image stored in the bundle
    @IBAction func sendImageAsResource(_ sender: Any) {
        
        // Call local function created
        sendImageAsResource()
    }
    
    // MARK: - Functions
    
    //send data to other users
    func sendData(data: String) {
        if mcSession.connectedPeers.count > 0 {
            if let textData = data.data(using: .utf8) {
                do {
                    //send data
                    try mcSession.send(textData, toPeers: mcSession.connectedPeers, with: .reliable)
                } catch let error as NSError {
                    //error sending data
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    func sendImageAsResource() {
        // 1. Get the url of the image in the project bundle. Change this if your image
        // is hosted in your documents directory or elsewhere.
        //
        // 2. Get all the connected peers. For testing purposes I am only getting the
        // first peer, you might need to loop through all your connected peers and send
        // the files individually.
        guard let imageURL = Bundle.main.url(forResource: "image2", withExtension: "jpg"),
              let guestPeerID = mcSession.connectedPeers.first else {
            return
        }
        
        // Retrieve the file size of the image
        if let fileSizeToTransfer = getFileSize(atURL: imageURL)
        {
            bytesExpectedToExchange = fileSizeToTransfer
            
            // Put the file size in a dictionary
            let fileTransferMeta = ["fileSize": bytesExpectedToExchange]
            
            // Convert the dictionary to a data object in order to send it via MultiPeer
            let encoder = JSONEncoder()
            
            if let JSONData = try? encoder.encode(fileTransferMeta)
            {
                // Send the file size to the guest users
                try? mcSession.send(JSONData, toPeers: mcSession.connectedPeers, with: .reliable)
            }
        }
        
        // Ideally for best reliability, you will want to develop some logic for the guest to
        // respond that it has received the file size and then you should initiate the transfer
        // to that peer only after you receive this confirmation. For now, I just add a delay
        // so that I am highly certain the guest has received this data for testing purposes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1)
        { [weak self] in
            self?.initiateFileTransfer(ofImage: imageURL, to: guestPeerID)
        }
    }
    
    func initiateFileTransfer(ofImage imageURL: URL, to guestPeerID: MCPeerID)
    {
        // Initialize and fire a timer to check the status of the file transfer every
        // 0.1 second
        checkProgressTimer = Timer.scheduledTimer(timeInterval: 0.1,
                                                  target: self,
                                                  selector: #selector(updateProgressStatus),
                                                  userInfo: nil,
                                                  repeats: true)
        
        // Call the sendResource function and send the image from the bundle
        // keeping hold of the returned progress object which we need to keep checking
        // using the timer
        fileTransferProgress = mcSession.sendResource(at: imageURL,
                                          withName: "image2.jpg",
                                          toPeer: guestPeerID,
                                          withCompletionHandler: { (error) in
                                            
                                            // Handle errors
                                            if let error = error as NSError?
                                            {
                                                print("Error: \(error.userInfo)")
                                                print("Error: \(error.localizedDescription)")
                                            }
                                            
                                          })
    }
    
    func getFileSize(atURL url: URL) -> Int?
    {
        let urlResourceValue = try? url.resourceValues(forKeys: [.fileSizeKey])
        
        return urlResourceValue?.fileSize
    }
    
    /// Function fired by the local checkProgressTimer object used to track the progress of the file transfer
    @objc
    func updateProgressStatus()
    {
        // Update the time elapsed. As mentioned earlier, a more reliable approach
        // might be to compare the time of a Date object from when the transfer started
        // to the time of a current Date object
        transferTimeElapsed += 0.1
        
        // Verify the progress variable is valid
        if let progress = fileTransferProgress
        {
            // Convert the progress into a percentage
            let percentCompleted = 100 * progress.fractionCompleted
            
            // Calculate the data exchanged sent in MegaBytes
            let dataExchangedInMB = (Double(bytesExpectedToExchange) * progress.fractionCompleted) / 1000000
            
            // We have exchanged 'dataExchangedInMB' MB of data in 'transferTimeElapsed' seconds
            // So we have to calculate how much data will be exchanged in 60 seconds using cross multiplication
            // For example:
            // 2 MB in 0.5s
            //  ?   in  1s
            // MB/s = (1 x 2) / 0.5 = 4 MB/s
            let megabytesPerSecond = (1 * dataExchangedInMB) / transferTimeElapsed
            
            // Convert dataExchangedInMB into a string rounded to 2 decimal places
            let dataExchangedInMBString = String(format: "%.2f", dataExchangedInMB)
            
            // Convert megabytesPerSecond into a string rounded to 2 decimal places
            let megabytesPerSecondString = String(format: "%.2f", megabytesPerSecond)
            
            // Update the progress an data exchanged on the UI
            numberLabel.text = "\(percentCompleted.rounded())% - \(dataExchangedInMBString) MB @ \(megabytesPerSecondString) MB/s"
            
            // This is mostly useful on the browser side to check if the file transfer
            // is complete so that we can safely deinit the timer, reset vars and update the UI
            if percentCompleted >= 100
            {
                numberLabel.text = "Transfer complete!"
                checkProgressTimer?.invalidate()
                checkProgressTimer = nil
                transferTimeElapsed = 0.0
            }
        }
    }
    
    //start hosting a new room
    func startHosting() {
        mcAdvertiserAssistant = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: "mp-numbers")
        mcAdvertiserAssistant.delegate = self
        mcAdvertiserAssistant.startAdvertisingPeer()
    }
    
    //join a room
    func joinSession() {
        let mcBrowser = MCBrowserViewController(serviceType: "mp-numbers", session: mcSession)
        mcBrowser.delegate = self
        present(mcBrowser, animated: true)
    }
    
    // MARK: - Session Methods
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connected:
            print("Connected: \(peerID.displayName)")
            
        case MCSessionState.connecting:
            print("Connecting: \(peerID.displayName)")
            
        case MCSessionState.notConnected:
            print("Not connected: \(peerID.displayName)")
            
        @unknown default:
            fatalError()
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        
        // Check if the guest has received file transfer data
        if let fileTransferMeta = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Int],
           let fileSizeToReceive = fileTransferMeta["fileSize"]
        {
            // Store the bytes to be received in a variable
            bytesExpectedToExchange = fileSizeToReceive
            print("Bytes expected to receive: \(fileSizeToReceive)")
            return
        }
        
        
        if let text = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                //display the text in the label
                self.numberLabel.text = text
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {
        
        // Store the progress object so that we can query it using the timer
        fileTransferProgress = progress
        
        // Launch the main thread
        DispatchQueue.main.async { [unowned self] in
            
            // Fire the timer to check the file transfer progress every 0.1 second
            self.checkProgressTimer = Timer.scheduledTimer(timeInterval: 0.1,
                                                           target: self,
                                                           selector: #selector(updateProgressStatus),
                                                           userInfo: nil,
                                                           repeats: true)
        }
    }
    
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {
        
        // Verify that we have a valid url. You should get a url to the file in
        // the tmp directory
        if let url = localURL
        {
            // Launch the main thread
            DispatchQueue.main.async { [weak self] in
                
                // Call a function to handle download completion
                self?.handleDownloadCompletion(withImageURL: url)
            }
        }
    }
    
    
    /// Handles the file transfer completion process on the advertiser/client side
    /// - Parameter url: URL of a file in the documents directory
    func handleDownloadCompletion(withImageURL url: URL) {
        
        // Debugging data
        print("Full URL: \(url.absoluteString)")
        
        numberLabel.text = "Transfer complete!"
        
        // Invalidate the timer
        checkProgressTimer?.invalidate()
        checkProgressTimer = nil
        
        // Reset the transfer timer
        transferTimeElapsed = 0.0
        
        // Set the UIImageView with the downloaded image
        imageView.image = UIImage(contentsOfFile: url.path)
    }
    
    // MARK: - Browser Methods
    
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true)
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true)
    }
    
    // MARK: - Advertiser Methods
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        //accept the connection/invitation
        invitationHandler(true, mcSession)
    }
        
}

