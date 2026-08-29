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
            // ── disguise/calculator 分支 ──────────────────────────
            // 对外表现为「计算器」App。
            // 在计算器中输入 102 再按 = 即可进入真实 mond 界面。
            CalcView()
                .environmentObject(state)
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
                .onAppear {
                    if !is_supported() {
                        // 保持静默：计算器不弹系统版本警告
                        print("(mond) warning: iOS version may not be fully supported")
                    }
                }
        }
    }
}
