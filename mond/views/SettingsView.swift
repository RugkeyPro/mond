//
//  SettingsView.swift
//  mond
//
//  Created by ruter on 18.07.26.
//

import SwiftUI
import PartyUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState
    
    @AppStorage("token") private var token: String = ""
    @AppStorage("method") private var method: String = "bad_query"
    @State private var show_confirm: Bool = false
    
    var valid: Bool {
        (sandbox_extension_consume(token) ?? -1) >= 0
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if let url = URL(string: "https://github.com/rooootdev/mond"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                               let files = primary["CFBundleIconFiles"] as? [String],
                               let icon = files.last,
                               let img = UIImage(named: icon) {
                                Image(uiImage: img)
                                    .resizable()
                                    .frame(width: 45, height: 45)
                                    .cornerRadius(12)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                                     ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                                     ?? "mond")
                                .font(.headline)
                                
                                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                Section {
                    LogView()
                        .modifier(TerminalPlatter())
                } header: {
                    Label("控制台日志", systemImage: "apple.terminal")
                }
                
                Section {
                    HStack {
                        TextField("沙盒扩展 Token", text: $token)
                        
                        Spacer()
                        
                        Button {
                            UIPasteboard.general.string = token
                        } label: {
                            Image(systemName: "document.on.document")
                        }
                    }
                    .contextMenu {
                        Text("类别: \(token.split(separator: ";").first { $0.contains("com.apple") }.map(String.init) ?? "未知")")
                        Text("路径: \(token.split(separator: ";").last.map(String.init) ?? "未知")")
                        
                        Button {
                            UIPasteboard.general.string = token
                        } label: {
                            Label("复制 Token", systemImage: "doc.on.doc")
                        }
                    }
                    .lineLimit(1)
                    
                    Button {
                        token = sandbox_extension_issue_file(path: TweakPaths.gestalt_dir) ?? "获取 Token 失败。"
                    } label: {
                        Text("生成 Token")
                    }
                    .disabled(!state.exploit_succeeded)
                } header: {
                    Label("沙盒 Token", systemImage: "key")
                } footer: {
                    if !token.isEmpty && token != "获取 Token 失败。" {
                        if valid {
                            Text("您的沙盒 Token 当前有效。")
                        } else {
                            Text("您的沙盒 Token 无效或已过期。")
                        }
                    }
                    
                    if !state.exploit_succeeded {
                        Text("由于漏洞利用未成功而禁用。请确认您的 iOS 版本是否受支持。")
                    }
                }
                
                Section {
                    Picker("漏洞机制", selection: $method) {
                        Text("bad_query").tag("bad_query")
                        Text("cmg").tag("cmg")
                    }
                    .pickerStyle(.segmented)
                    
                    Button {
                        _ = grant_mg_write()
                    } label: {
                        Text("执行漏洞利用")
                    }
                } header: {
                    Label("漏洞利用机制", systemImage: "wrench.and.screwdriver")
                } footer: {
                    Text(method == "cmg" ? "**CMG:** 支持 iOS 27.0 b1 - b4。建议优先使用 bad_query 方式..." : "**bad_query:** 支持 iOS 27.0 b1 - b4。由 [forcequit](https://github.com/forcequitOS) 开发。")
                }
                
                Section {
                    Button {
                        show_confirm = true
                    } label: {
                        Text("注销主屏幕 (Respring)")
                    }
                } header: {
                    Label("系统工具", systemImage: "wrench.and.screwdriver")
                }
                
                Section {
                    Button {
                        DispatchQueue.global(qos: .userInitiated).async {
                            run_full_diagnostics()
                        }
                    } label: {
                        Label("运行完整诊断 (真机逃逸测试)", systemImage: "stethoscope")
                    }
                } header: {
                    Label("诊断与调试 (iOS 26/27 逃逸检测)", systemImage: "ladybug")
                } footer: {
                    Text("全面探测 MCM 路径穿越、MCM 符号、沙盒扩展签发、MDM 绕过、UUID 物理路径以及文件真实写入能力。结果将实时输出至日志控制台。长按日志即可复制全部诊断报告。")
                }

                Section {
                    CreditsRow(name: "roooot", role: "主要开发者", profile: URL(string: "https://github.com/rooootdev")!)
                    CreditsRow(name: "forcequit", role: "bad_query 漏洞发现与实现", profile: URL(string: "https://github.com/forcequitOS")!)
                    CreditsRow(name: "johnny", role: "MCM 漏洞类研究与贡献", profile: URL(string: "https://github.com/0xjohnnydev")!)
                    CreditsRow(name: "jailbreak.party", role: "PartyUI 与 GestaltView 界面库", profile: URL(string: "https://github.com/jailbreakdotparty")!)
                } header: {
                    Label("致谢与鸣谢", systemImage: "person.3.fill")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Text("完成")
                        }
                    }
                }
            }
            .alert("确定要注销吗？", isPresented: $show_confirm) {
                Button("取消") {
                    show_confirm = false
                }
                
                Button("确认注销") {
                    state.respring()
                }
            } message: {
                Text("确认立即注销主屏幕（Respring）以使修改生效。")
            }
        }
    }
}

struct CreditsRow: View {
    let name: String
    let role: String
    let profile: URL

    private var pfp: URL? {
        URL(string: profile.absoluteString + ".png")
    }

    var body: some View {
        HStack(alignment: .top) {
            AsyncImage(url: pfp) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)

                Text(role)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .onTapGesture {
            UIApplication.shared.open(profile)
        }
    }
}
