//
//  ContentView.swift
//  EasyDisplay
//
//  Created by Vincent on 2026/10/31.
//

import SwiftUI
struct MacSettingsView: View {
    @StateObject private var server = MacBonjourServer()
    @State private var serverName: String = ""
    @State private var portString: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Mac 原生副屏服务端")
                .font(.title).bold()
            Form {
                Section(header: Text("服务广播配置")) {
                    TextField("服务器显示名称", text: $serverName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(server.isRunning)
                    
                    TextField("监听端口号 (1024-65355)", text: $portString)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(server.isRunning)
                }
            }
            HStack {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(server.isRunning ? "正在将 Mac 显卡画面推送到局域网..." : "已停止服务")
                    .foregroundColor(.secondary)
                Spacer()
                if server.isRunning {
                    Button("停止服务") { server.stopServer() }
                        .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    Button("保存并启动") {
                        if let portValue = UInt16(portString), !serverName.isEmpty {
                            server.startServer(name: serverName, port: portValue)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(serverName.isEmpty || UInt16(portString) == nil)
                }
            }
        }
        .padding(30).frame(width: 450, height: 280)
        .onAppear {
            serverName = server.currentName
            portString = String(server.currentPort)
        }
    }
}


