//
//  mond.swift
//  mond
//
//  Created by ruter on 16.07.26.
//

import SwiftUI
import PartyUI

var pipe = Pipe()
var sema = DispatchSemaphore(value: 0)
var fm = FileManager.default

var path: String {
    let url = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("test.txt")

    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    return url.path
} 

@main
struct mond: App {
    @StateObject private var state = AppState()
    
    init() {
        UserDefaults.standard.register(defaults: ["exploit_method": "bad_query"])
        if !is_debugged() {
            setvbuf(stdout, nil, _IONBF, 0)
            dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .onAppear() {
                    if !is_supported() {
                        Alertinator.shared.alert(title: "当前系统可能不受支持！", body: "您的 iOS 版本可能不完全兼容 mond。\nmond 支持 iOS 17.0 - 27.x。")
                    }
                }
                .overlay {
                    if state.show_respring {
                        RespringView()
                            .brightness(-1.0)
                            .ignoresSafeArea()
                            .onAppear {
                                print("(respring) respringing now...")
                            }
                    }
                }
        }
    }
}
