//
//  ContentView.swift
//  EasyDisplayClient
//
//  Created by Vincent on 2026/10/31.
//

import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var finder = iPadBonjourBrowser()
    @State private var connectedDeviceName: String? = nil
    @State private var isConnecting = false
    
    func getDeviceName(from endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint { return name }
        return "Mac 主机"
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if let activeConnection = connectedDeviceName {
                    ZStack(alignment: .bottom) {
                        // 🚀 彻底激活：高清无黑边硬解分屏画布
                        VideoRenderView(finder: finder)
                            .edgesIgnoringSafeArea(.all)
                            .background(Color.black)
                        
                        Button("退出副屏系统") {
                            finder.stopScanning()
                            connectedDeviceName = nil
                            finder.startScanning()
                        }
                        .padding().background(Color.red.opacity(0.8))
                        .foregroundColor(.white).cornerRadius(10).padding(.bottom, 30)
                    }
                } else {
                    List(finder.discoveredServers, id: \.endpoint) { server in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(getDeviceName(from: server.endpoint)).font(.headline)
                                Text("VRAM 显卡硬编无感通道").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if isConnecting {
                                ProgressView()
                            } else {
                                Button("一键连接") {
                                    isConnecting = true
                                    finder.connectToServer(result: server) { success in
                                        isConnecting = false
                                        if success {
                                            connectedDeviceName = getDeviceName(from: server.endpoint)
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .overlay {
                        if finder.discoveredServers.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("雷达正在搜寻局域网副屏服务...").foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("副屏连接中心")
            .onAppear { finder.startScanning() }
            .onDisappear { finder.stopScanning() }
        }
    }
}
