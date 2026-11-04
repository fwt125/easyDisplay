//
//  MacBonjourServer.swift
//  EasyDisplay
//
//  Created by Vincent on 2026/10/31.
//

import Foundation
import Network
import Combine
import ScreenCaptureKit
import VideoToolbox

class MacBonjourServer: NSObject, ObservableObject, SCStreamOutput {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var stream: SCStream?
    private var compressionSession: VTCompressionSession?
    
    @Published var isRunning = false
    @Published var currentName = ""
    @Published var currentPort: UInt16 = 7001
    
    override init() {
        super.init()
        self.currentName = UserDefaults.standard.string(forKey: "ServerName") ?? Host.current().localizedName ?? "My Mac Display"
        let savedPort = UserDefaults.standard.integer(forKey: "ServerPort")
        self.currentPort = savedPort != 0 ? UInt16(savedPort) : 7001
    }
    
    func startServer(name: String, port: UInt16) {
        if isRunning { stopServer() }
        UserDefaults.standard.set(name, forKey: "ServerName")
        UserDefaults.standard.set(Int(port), forKey: "ServerPort")
        self.currentName = name
        self.currentPort = port
        
        do {
            let parameters = NWParameters.tcp
            self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            self.listener?.service = NWListener.Service(name: name, type: "_easydisplay._tcp")
            
            self.listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async { self?.isRunning = (state == .ready) }
            }
            
            self.listener?.newConnectionHandler = { [weak self] newConnection in
                self?.activeConnection = newConnection
                newConnection.start(queue: .main)
                self?.startCaptureAndEncoding()
            }
            
            self.listener?.start(queue: .main)
        } catch { print("启动异常: \(error)") }
    }
    
    private func startCaptureAndEncoding() {
        SCShareableContent.getWithCompletionHandler { [weak self] content, error in
            guard let self = self, let display = content?.displays.first else { return }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            
            let status = VTCompressionSessionCreate(
                allocator: nil,
                width: Int32(display.width),
                height: Int32(display.height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: { outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
                    guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
                    let serverObj = Unmanaged<MacBonjourServer>.fromOpaque(refCon).takeUnretainedValue()
                    serverObj.sendSampleBuffer(sampleBuffer)
                },
                refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                compressionSessionOut: &self.compressionSession
            )
            
            guard status == noErr, let session = self.compressionSession else { return }
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
            VTCompressionSessionPrepareToEncodeFrames(session)
            
            self.stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try? self.stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "video-encode"))
            self.stream?.startCapture()
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let session = compressionSession else { return }
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        VTCompressionSessionEncodeFrame(session, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, duration: .invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
    }
    
    func sendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // 💡 自动判断并提取关键帧的描述包（包含 iPad 解码最需要的 avcC 原子头信息）
        var descriptionData = Data()
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var size: Int = 0
            var count: Int = 0
            var naluHeaderLength: Int32 = 0
            
            // 🛠️ 彻底修复：将旧版 index: 标签精准匹配为新版编译器的 parameterSetIndex:
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: &size, parameterSetCountOut: &count, nalUnitHeaderLengthOut: &naluHeaderLength) == noErr {
                // 如果是关键帧，将格式描述本身的数据直接提取包装成前置头发送
                var spsSize: Int = 0
                var spsPointer: UnsafePointer<UInt8>?
                var ppsSize: Int = 0
                var ppsPointer: UnsafePointer<UInt8>?
                
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                
                if let sps = spsPointer, let pps = ppsPointer {
                    descriptionData.append(sps, count: spsSize)
                    descriptionData.append(pps, count: ppsSize)
                }
            }
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
        
        if status == noErr, let dataPointer = pointer, length > 0 {
            let bodyData = Data(bytes: dataPointer, count: length)
            
            // 拼接完整的格式包：[4字节总长度] + [1字节标记位: 1代表带头关键帧, 0代表普通帧] + [可选的avcC头信息] + [真实的 H.264 像素数据]
            let hasHeader: UInt8 = descriptionData.isEmpty ? 0 : 1
            var packetBody = Data([hasHeader])
            if hasHeader == 1 {
                var headerSize = Int32(descriptionData.count).bigEndian
                packetBody.append(Data(bytes: &headerSize, count: 4))
                packetBody.append(descriptionData)
            }
            packetBody.append(bodyData)
            
            var totalSize = Int32(packetBody.count).bigEndian
            var finalPacket = Data(bytes: &totalSize, count: 4)
            finalPacket.append(packetBody)
            
            activeConnection?.send(content: finalPacket, completion: .contentProcessed({ _ in }))
        }
    }
    
    func stopServer() {
        stream?.stopCapture()
        stream = nil
        if let session = compressionSession { VTCompressionSessionInvalidate(session) }
        compressionSession = nil
        activeConnection?.cancel()
        listener?.cancel()
        isRunning = false
    }
}

