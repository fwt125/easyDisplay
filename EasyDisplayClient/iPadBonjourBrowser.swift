//
//  iPadBonjourBrowser.swift
//  EasyDisplayClient
//
//  Created by Vincent on 2026/10/31.
//

import Foundation
import Network
import Combine
import AVFoundation

class iPadBonjourBrowser: ObservableObject {
    private var browser: NWBrowser?
    @Published var discoveredServers: [NWBrowser.Result] = []
    var activeConnection: NWConnection?
    
    var onFrameReceived: ((CMSampleBuffer) -> Void)?
    private var bufferData = Data()
    private var formatDescription: CMVideoFormatDescription?
    
    func startScanning() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_easydisplay._tcp", domain: "local.")
        self.browser = NWBrowser(for: descriptor, using: NWParameters())
        self.browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async { self?.discoveredServers = Array(results) }
        }
        self.browser?.start(queue: .main)
    }
    
    func connectToServer(result: NWBrowser.Result, completion: @escaping (Bool) -> Void) {
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        self.activeConnection = connection
        connection.stateUpdateHandler = { state in
            if state == .ready {
                DispatchQueue.main.async { completion(true) }
                self.readNextPacket()
            } else if case .failed = state {
                DispatchQueue.main.async { completion(false) }
            }
        }
        connection.start(queue: .main)
    }
    
    private func readNextPacket() {
        activeConnection?.receive(minimumIncompleteLength: 4, maximumLength: 65535) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, error == nil else { return }
            self.bufferData.append(data)
            
            while self.bufferData.count >= 4 {
                let size = Int(Int32(bigEndian: self.bufferData.withUnsafeBytes { $0.load(as: Int32.self) }))
                if self.bufferData.count >= (size + 4) {
                    let packetData = self.bufferData.subdata(in: 4..<(size + 4))
                    self.bufferData.removeSubrange(0..<(size + 4))
                    self.parseIncomingPacket(packetData)
                } else { break }
            }
            if !isComplete { self.readNextPacket() }
        }
    }
    
    private func parseIncomingPacket(_ packet: Data) {
        guard packet.count > 1 else { return }
        let hasHeader = packet[0]
        var videoPayload = Data()
        
        if hasHeader == 1 {
            let headerSize = Int(Int32(bigEndian: packet.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: Int32.self) }))
            let avcCHeaderData = packet.subdata(in: 5..<(5 + headerSize))
            videoPayload = packet.subdata(in: (5 + headerSize)..<packet.count)
            
            let extensions = [
                kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: [
                    "avcC": avcCHeaderData
                ]
            ] as CFDictionary
            
            var newFormat: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCMVideoCodecType_H264,
                width: 1920,
                height: 1080,
                extensions: extensions,
                formatDescriptionOut: &newFormat
            )
            if status == noErr { self.formatDescription = newFormat }
        } else {
            videoPayload = packet.subdata(in: 1..<packet.count)
        }
        
        guard let format = self.formatDescription else { return }
        renderPayload(videoPayload, with: format)
    }
    
    private func renderPayload(_ data: Data, with format: CMVideoFormatDescription) {
        let blockLength = data.count
        let memoryBlock = UnsafeMutableRawPointer.allocate(byteCount: blockLength, alignment: MemoryLayout<UInt8>.alignment)
        data.withUnsafeBytes { rawBuffer in
            if let base = rawBuffer.baseAddress { memoryBlock.copyMemory(from: base, byteCount: blockLength) }
        }
        
        var blockBuffer: CMBlockBuffer?
        let bufferStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: memoryBlock,
            blockLength: blockLength,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: blockLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        if bufferStatus == kCMBlockBufferNoErr, let bBuffer = blockBuffer {
            var timing = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: CMTime(value: Int64(CACurrentMediaTime() * 1000), timescale: 1000),
                decodeTimeStamp: .invalid
            )
            var sampleBuffer: CMSampleBuffer?
            var sampleSize = blockLength
            
            let createStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: bBuffer,
                formatDescription: format,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer
            )
            
            if createStatus == noErr, let sb = sampleBuffer {
                // 🛠️ 终极对齐：从数组中精准提取出第一个字典指针，彻底修复类型无法转换的报错
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true)
                if let attachmentsArray = attachments as? [CFMutableDictionary], let firstAttachment = attachmentsArray.first {
                    let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
                    let value = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                    CFDictionarySetValue(firstAttachment, key, value)
                }
                DispatchQueue.main.async { self.onFrameReceived?(sb) }
            }
        }
    }
    
    func stopScanning() { browser?.cancel(); activeConnection?.cancel(); browser = nil }
}
