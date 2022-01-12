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
        guard let imageURL = Bundle.main.url(forResource: "image", withExtension: "jpg"),
              let clientPeerID = mcSession.connectedPeers.first else {
            return
        }
        
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
                                          withName: "image.jpg",
                                          toPeer: clientPeerID,
                                          withCompletionHandler: { (error) in
                                            
                                            // Handle errors
                                            if let error = error as NSError?
                                            {
                                                print("Error: \(error.userInfo)")
                                                print("Error: \(error.localizedDescription)")
                                            }
                                            
                                          })
    }
    
    /// Function fired by the local checkProgressTimer object used to track the progress of the file transfer
    @objc
    func updateProgressStatus()
    {
        // Verify the progress variable is valid
        if let progress = fileTransferProgress
        {
            // Convert the progress into a percentage
            let percentCompleted = 100 * progress.fractionCompleted
            
            // Update the progress on the UI
            numberLabel.text = "\(percentCompleted.rounded())%"
            
            // This is mostly useful on the browser side to check if the file transfer
            // is complete so that we can safely deinit the timer and update the UI
            if percentCompleted >= 100
            {
                numberLabel.text = "Transfer complete"
                checkProgressTimer?.invalidate()
                checkProgressTimer = nil
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
        //data received
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

