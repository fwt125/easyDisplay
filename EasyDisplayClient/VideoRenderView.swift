//
//  VideoRenderView.swift
//  EasyDisplayClient
//
//  Created by Vincent on 2026/10/31.
//

import SwiftUI
import AVFoundation

struct VideoRenderView: UIViewRepresentable {
    @ObservedObject var finder: iPadBonjourBrowser
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspectFill // 让画面完美无黑边铺满 iPad 全屏
        
        finder.onFrameReceived = { sampleBuffer in
            if displayLayer.isReadyForMoreMediaData {
                displayLayer.enqueue(sampleBuffer)
            }
        }
        
        view.layer.addSublayer(displayLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = uiView.bounds
        }
    }
}
