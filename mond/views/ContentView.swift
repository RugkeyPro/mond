//
//  ContentView.swift
//  mond
//
//  Created by ruter on 16.07.26.
//

import SwiftUI
import PartyUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("mg_devicename") private var mg_devicename: String = ""
    @AppStorage("token") private var token: String = ""
    
    @State private var mg_dict_now: NSMutableDictionary = NSMutableDictionary()
    @State private var is_valid: Bool = false
    
    @State private var og_st: Int = 0
    @State private var selected_st: String = ""
    
    @State private var enable_devicename: Bool = false
    @State private var og_devicename: String = ""
    @State private var product_type: String = ""
    
    @State private var show_settings: Bool = false
    @State private var mdm_backup_exists: Bool = false
    
    private var mg_valid: Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: TweakPaths.gestalt)) else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil
    }
    
    private var mg_empty: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: TweakPaths.gestalt),
              let size = attributes[.size] as? UInt64 else { return false }

        return size == 0
    }
    
    var valid: Bool {
        (sandbox_extension_consume(token) ?? -1) >= 0
    }

    var selected_st_value: Int {
        switch selected_st {
            case "og":
                return og_st
            case "no_dynamic_island":
                return 0
            case "14p":
                return 2436
            case "14pm":
                return 2796
            case "15pm":
                return 2976
            case "16p":
                return 2622
            case "16pm":
                return 2868
            case "air":
                return 2736
            case "x":
                return 2436
            default:
                return 0
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FileBrowserHomeView()
                    } label: {
                        Label("文件浏览器", systemImage: "folder")
                    }
                } header: {
                    Label("文件系统", systemImage: "internaldrive")
                } footer: {
                    Text("浏览应用沙盒目录或通过 bad_query 访问精确的 /private/var 系统路径；受控写入需通过独立写操作探针验证。")
                }

                Section {
                    NavigationLink {
                        FileBrowserView(root: BrowserRoot(
                            title: "MDM 描述文件存储",
                            subtitle: "Apple 商务管理 / 校园教务管理所使用的描述文件存储目录",
                            icon: "shield.lefthalf.filled",
                            url: URL(fileURLWithPath: TweakPaths.mdm_profiles, isDirectory: true),
                            mode: .systemManaged
                        ))
                    } label: {
                        Label("MDM 描述文件", systemImage: "shield.lefthalf.filled")
                    }

                    Button {
                        mdm_neuter()
                    } label: {
                        Label("绕过 MDM (将描述文件覆盖为空字典)", systemImage: "shield.slash")
                            .foregroundStyle(.red)
                    }

                    if mdm_backup_exists {
                        Button {
                            mdm_restore_action()
                        } label: {
                            Label("从安全备份还原 MDM 描述文件", systemImage: "arrow.counterclockwise.shield")
                                .foregroundStyle(.blue)
                        }
                    }
                } header: {
                    Label("MDM 监管管理", systemImage: "lock.shield")
                } footer: {
                    Text("与直接删除文件（易触发系统守护进程自愈恢复）不同，‘绕过 MDM’ 会将描述文件覆盖为空 Payload。修改前将自动创建安全备份。修改后需要重启设备以生效。")
                }

                if !mg_valid || mg_empty {
                    Section {
                        if mg_empty {
                            PlainAlert(title: "请勿重启设备！", icon: "exclamationmark.triangle.fill", text: "您的 MobileGestalt.plist 似乎为空文件。", color: Color.yellow)
                        }
                        
                        if !mg_valid {
                            PlainAlert(title: "请勿重启设备！", icon: "exclamationmark.triangle.fill", text: "您的 MobileGestalt.plist 数据格式似乎无效。", color: Color.yellow)
                        }
                    } header: {
                        Label("安全警告", systemImage: "exclamationmark.triangle")
                    } footer: {
                        Text("此时重启可能导致设备陷入无限重启（Bootloop）。请尝试点击‘恢复默认配置’。如果警告仍未消除，请通过备份文件恢复。")
                    }
                }
                
                Section {
                    Button {
                        mg_apply()
                    } label: {
                        Text("应用修改")
                    }
                    
                    Button {
                        mg_revert()
                    } label: {
                        Text("恢复默认配置")
                    }
                } footer: {
                    Text("**警告：** 如果配置不当，这些修改项可能导致设备部分功能异常或轻度变砖（Softbrick）！请务必知悉。")
                }
                
                Section {
                    Picker(selection: $selected_st) {
                        Text("原机默认 (\(og_st))").tag("og")
                        
                        if is_device_good() {
                            Text("关闭灵动岛").tag("no_dynamic_island")
                        }
                    
                        Text("iPhone 14 Pro").tag("14p")
                        Text("iPhone 14 Pro Max").tag("14pm")
                        Text("iPhone 15 Pro Max").tag("15pm")
                    
                        if doubleSystemVersion() >= 18.0 {
                            Text("iPhone 16 Pro").tag("16p")
                            Text("iPhone 16 Pro Max").tag("16pm")
                        }
                    
                        if doubleSystemVersion() >= 26.0 {
                            Text("iPhone Air").tag("air")
                        }
                    
                        if hasHomeButton() {
                            Text("iPhone X 全面屏手势").tag("x")
                        }
                    } label: {
                        HStack {
                            Text("机型子类型 (Subtype)")
                            Spacer()
                        }
                    }
                    
                    Toggle("自定义设备名称", isOn: $enable_devicename)
                    
                    if enable_devicename {
                        TextField("设备型号名称", text: $mg_devicename)
                    }
                } header: {
                    Label("机型外观与型号", systemImage: "paintbrush.pointed")
                }
                
                // basic tweak toggles
                Section {
                    PlainToggle(text: "灵动岛 (Dynamic Island)", minSupportedVersion: 19.0, isOn: mg_key_binding(["YlEtTtHlNesRBMal1CqRaA"]))
                    PlainToggle(text: "全天候显示 (AOD)", minSupportedVersion: 18.0, isOn: mg_key_binding(["j8/Omm6s1lsmTDFsXjsBfA", "2OOJf1VhaM7NxfRok3HbWQ"]))
                    PlainToggle(text: "全天候显示鲜艳度 (AOD Vibrancy)", minSupportedVersion: 18.0, isOn: mg_key_binding(["ykpu7qyhqFweVMKtxNylWA"]))
                    PlainToggle(text: "80% 充电上限", minSupportedVersion: 17.0, isOn: mg_key_binding(["37NVydb//GP/GrhuTN+exg"]))
                    PlainToggle(text: "开机提示音 (Boot Chime)", isOn: mg_key_binding(["QHxt+hGLaBPbQJbXiUJX3w"]))
                    PlainToggle(text: "Liquid Glass 低电量模式", minSupportedVersion: 19.0, isOn: mg_key_binding(["SAGvsp6O6kAQ4fEfDJpC4Q"]))
                } header: {
                    Label("软件特性", systemImage: "gearshape")
                }
                
                Section {
                    PlainToggle(text: "相机控制按键 (Camera Control)", minSupportedVersion: 18.0, isOn: mg_key_binding(["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"]))
                    PlainToggle(text: "操作按钮 (Action Button)", minSupportedVersion: 17.0, isOn: mg_key_binding(["cT44WE1EohiwRzhsZ8xEsw"]))
                    PlainToggle(text: "车祸检测 (Crash Detection)", isOn: mg_key_binding(["HCzWusHQwZDea6nNhaKndw"]))
                    if hasHomeButton() {
                        PlainToggle(text: "轻点唤醒 (Tap to Wake)", isOn: mg_key_binding(["yZf3GTRMGTuwSV/lD7Cagw"]))
                    }
                    PlainToggle(text: "PWM 防频闪调光", minSupportedVersion: 19.0, isOn: mg_key_binding(["6IejgN+1Fmu5/QrZFOIeNw"]))
                } header: {
                    Label("硬件特性", systemImage: "iphone")
                }

                
                Section {
                    PlainToggle(text: "安全研究设备 UI (SRD UI)", minSupportedVersion: 26.0, isOn: mg_key_binding(["XYlJKKkj2hztRP1NWWnhlw"]))
                    
                    PlainToggle(
                        text: "去除地区限制 (拍照静音/美版特性)",
                        infoType: .info,
                        infoMessage: "该功能用于解除区域性功能限制（如日韩版拍照快门声）。请在遵守当地法律法规的前提下使用。",
                        isOn: mg_region_restrict_binding()
                    )
                    
                    PlainToggle(
                        text: "Apple 智能 (Apple Intelligence)",
                        infoType: .info,
                        infoMessage: "Apple Intelligence 组件激活在部分系统版本可能受服务器限制或不可用。",
                        minSupportedVersion: 18.1,
                        isOn: mg_key_binding(["A62OafQ85EJAiiqKn4agtg"])
                    )
                    
                    HStack(spacing: 10) {
                        Picker("伪装机型", selection: $product_type) {
                            Text("原机默认 (\(machine_name()))").tag(machine_name())
                            if UIDevice.current.userInterfaceIdiom == .pad {
                                if doubleSystemVersion() >= 17.4 {
                                    Text("iPad Pro 11-inch (M4)").tag("iPad16,3")
                                    Text("iPad Pro 11-inch (M4, 蜂窝版)").tag("iPad16,4")
                                }
                                Text("iPad Pro 11-inch (第4代)").tag("iPad14,3")
                                Text("iPad Pro 11-inch (第4代, 蜂窝版)").tag("iPad14,4")
                            } else {
                                Text("iPhone 15 Pro").tag("iPhone16,1")
                                Text("iPhone 15 Pro Max").tag("iPhone16,2")
                                if doubleSystemVersion() >= 18.0 {
                                    Text("iPhone 16").tag("iPhone17,3")
                                    Text("iPhone 16 Plus").tag("iPhone17,4")
                                    Text("iPhone 16 Pro").tag("iPhone17,1")
                                    Text("iPhone 16 Pro Max").tag("iPhone17,2")
                                }
                                if doubleSystemVersion() >= 19.0 {
                                    Text("iPhone 17").tag("iPhone18,3")
                                    Text("iPhone 17 Pro").tag("iPhone18,1")
                                    Text("iPhone 17 Pro Max").tag("iPhone18,2")
                                    Text("iPhone Air").tag("iPhone18,4")
                                }
                            }
                        }
                        
                        Button {
                            Alertinator.shared.alert(
                                title: "机型伪装说明",
                                body: "仅在需要激活 Apple Intelligence 下载资格时伪装机型。此操作可能会导致面容 ID（Face ID）暂时不可用。如果取消伪装且希望保留已下载的智能模型，请切勿重新进入系统‘设置 -> Apple 智能与 Siri’菜单。"
                            )
                        } label: {
                            Image(systemName: "info.circle")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("资格与区域", systemImage: "checklist")
                }
                
                Section {
                    let cache_extra = mg_dict_now["CacheExtra"] as? NSMutableDictionary
                    
                    PlainToggle(text: "允许安装 iPadOS 专属 App", isOn: mg_key_binding(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, default_val: [1], on_val: [1, 2]))
                    PlainToggle(text: "Apple Pencil 随手写设置", isOn: mg_key_binding(["yhHcB0iH0d1XzPO/CFd3ow"]))
                    
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        PlainToggle(text: "台前调度 (Stage Manager)", isOn: mg_key_binding(["qeaj75wk3HF4DwQ8qbIi7g"]))
                    }
                    PlainToggle(
                        text: "iPadOS 界面 (TrollPad)",
                        infoType: .warning,
                        infoMessage: "这是一个高风险的修改项！如果您的设备设置了字母数字混合锁屏密码，请绝对不要开启此选项！请务必不要关闭‘在台前调度中显示程序坞’，否则设备横屏旋转时将导致 Bootloop（无限重启）！此外，部分用户反馈在开启 iPadOS UI 并点击台前调度后可能进入恢复模式。请谨慎评估风险后操作。",
                        isOn: mg_trollpad_binding()
                    )
                    .disabled(cache_extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone")
                } header: {
                    Label("iPadOS 特性", systemImage: "ipad")
                }
                
                Section {
                    PlainToggle(text: "内部存储选项 (Internal Storage)", isOn: mg_key_binding(["LBJfwOEzExRxzlAnSuI7eg"]))
                    PlainToggle(text: "AppleInternal 内部功能", isOn: mg_internal_binding())
                    PlainToggle(text: "全局 Metal 性能监视 HUD", isOn: mg_key_binding(["EqrsVvjcYDdxHBiQmGhAWw"]))
                } header: {
                    Label("内部调试", systemImage: "ant")
                }
            }
            .navigationTitle("mond")
            .tint(Color("AccentColor"))
            .onAppear {
                mdm_backup_exists = has_mdm_backups()
                if !valid {
                    state.exploit_succeeded = grant_mg_write() >= 0
                } else {
                    print("(mond) valid token saved, skipping exploit")
                    state.exploit_succeeded = true
                }
                
                mg_load()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            show_settings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .sheet(isPresented: $show_settings) {
                SettingsView()
            }
        }
    }
    
    private enum MGViewError: Error, LocalizedError {
        case missingArtworkSubtype
        case missingArtworkDeviceName
        
        var errorDescription: String? {
            switch self {
            case .missingArtworkSubtype:
                return "获取设备 ArtworkDeviceSubType 失败！"
            case .missingArtworkDeviceName:
                return "获取设备 ArtworkDeviceProductDescription 失败！"
            }
        }
    }
    
    private func mg_load() {
        do {
            let mg_url_now = URL(fileURLWithPath: TweakPaths.gestalt)
            mg_dict_now = try NSMutableDictionary(contentsOf: mg_url_now, error: ())
            
            // this'll cache gestalt and put it in a safe place
            let mg_url_saved = URL(fileURLWithPath: AppPaths.backups).appendingPathComponent("SavedGestalt.plist")
            
            if !FileManager.default.fileExists(atPath: mg_url_saved.path) {
                try FileManager.default.copyItem(at: mg_url_now, to: mg_url_saved)
            }
            
            // get original gestalt values
            let mg_saved_dict = try NSMutableDictionary(contentsOf: mg_url_saved, error: ())
            let og_cache_extra = mg_saved_dict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            let og_artwork = og_cache_extra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            
            guard let og_subtype = og_artwork["ArtworkDeviceSubType"] as? Int else { throw MGViewError.missingArtworkSubtype }
            og_st = og_subtype
            
            guard let og_devicename = og_artwork["ArtworkDeviceProductDescription"] as? String else { throw MGViewError.missingArtworkDeviceName }
            
            let cache_extra = mg_dict_now["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            let artwork = cache_extra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            
            let current_subtype = artwork["ArtworkDeviceSubType"] as? Int ?? og_subtype
            let subtype_tags: [Int: String] = [
                0: "no_dynamic_island",
                2436: "14p",
                2796: "14pm",
                2976: "15pm",
                2622: "16p",
                2868: "16pm",
                2736: "air",
            ]
            selected_st = current_subtype == og_subtype ? "og" : (subtype_tags[current_subtype] ?? "og")
            mg_devicename = artwork["ArtworkDeviceProductDescription"] as? String ?? og_devicename
            
            // assume it's been changed
            if mg_devicename != og_devicename {
                enable_devicename = true
            }
            
            if let productType = cache_extra["h9jDsbgj7xIVeIQ8S3/X3Q"] as? String, !productType.isEmpty {
                product_type = productType
            } else {
                product_type = machine_name()
            }
        } catch {
            print("(mg) failed to load data: \(error)")
            Alertinator.shared.alert(title: "无法加载当前 MobileGestalt！", body: "请重启应用后重试。详情请查看控制台日志。")
        }
    }
    
    private func mg_apply() {
        do {
            let cache_extra = mg_dict_now["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
            if !product_type.isEmpty {
                cache_extra["h9jDsbgj7xIVeIQ8S3/X3Q"] = product_type
            }
            
            let artwork_dict = cache_extra["oPeik/9e8lQWMszEjbPzng"] as? NSMutableDictionary ?? NSMutableDictionary()
            artwork_dict["ArtworkDeviceSubType"] = selected_st_value
            
            if enable_devicename {
                artwork_dict["ArtworkDeviceProductDescription"] = mg_devicename
            }
            
            let data = try PropertyListSerialization.data(fromPropertyList: mg_dict_now, format: .xml, options: 0)

            try mg_write(data)
            mg_dict_now = NSMutableDictionary()
            enable_devicename = false

            print("(mg) successfully overwrote mobilegestalt!")
            Alertinator.shared.alert(title: "修改应用成功！", body: "请注销主屏幕（Respring）以使修改生效。部分系统选项可能需要重启设备方可完全应用。", actionLabel: "注销 (Respring)", action: {
                state.respring()
            })
        } catch {
            print("(mg) failed to apply mobilegestalt: \(error)")
            Alertinator.shared.alert(title: "应用 MobileGestalt 失败！", body: "请重启应用后重试，详情请查看控制台日志。")
        }
    }
    
    private func mg_revert() {
        do {
            let backup_url = URL(fileURLWithPath: AppPaths.backups).appendingPathComponent("SavedGestalt.plist")
            let backup_data = try Data(contentsOf: backup_url)
            try mg_write(backup_data)

            print("(mg) successfully reverted mobilegestalt!)")
            Alertinator.shared.alert(title: "成功恢复默认配置！", body: "请重启设备以使修改完全生效。")
        } catch {
            print("(mg) failed to revert mobilegestalt: \(error)")
            Alertinator.shared.alert(title: "恢复 MobileGestalt 失败！", body: "详情请查看控制台错误日志。")
        }
    }

    private func mg_write(_ data: Data) throws {
        let target_url = URL(fileURLWithPath: TweakPaths.gestalt)
        let temp_url = target_url.deletingLastPathComponent()
            .appendingPathComponent(".\(target_url.lastPathComponent).\(UUID().uuidString).tmp")

        try data.write(to: temp_url, options: [.withoutOverwriting])
        defer { try? fm.removeItem(at: temp_url) }

        if fm.fileExists(atPath: target_url.path) {
            _ = try fm.replaceItemAt(target_url, withItemAt: temp_url)
        } else {
            try fm.moveItem(at: temp_url, to: target_url)
        }
    }
    
    private func mg_key_binding<T: Equatable>(_ keys: [String], type: T.Type = Int.self, default_val: T? = 0, on_val: T? = 1) -> Binding<Bool>  {
        guard let cache_extra = mg_dict_now["CacheExtra"] as? NSMutableDictionary else {
            return .constant(false)
        }
        
        return Binding(get: {
            if let value = cache_extra[keys.first!] as? T?, let on_val {
                return value == on_val
            }
            
            return false
        }, set: { enabled in
            for key in keys {
                if enabled {
                    cache_extra[key] = on_val
                } else {
                    cache_extra.removeObject(forKey: key)
                }
            }
        })
    }
    
    private func mg_trollpad_binding() -> Binding<Bool> {
        guard let cache_data = mg_dict_now["CacheData"] as? NSMutableData,
                let cache_extra = mg_dict_now["CacheExtra"] as? NSMutableDictionary else {
            return .constant(false)
        }
        
        let value_off = cache_data_offset("mtrAoWJ3gsq+I90ZnQ0vQw")
        let keys = [
            "uKc7FPnEO++lVhHWHFlGbQ", // ipad
            "mG0AnH/Vy1veoqoLRAIgTA", // MedusaFloatingLiveAppCapability
            "UCG5MkVahJxG1YULbbd5Bg", // MedusaOverlayAppCapability
            "ZYqko/XM5zD3XBfN5RmaXA", // MedusaPinnedAppCapability
            "nVh/gwNpy7Jv1NOk00CMrw", // MedusaPIPCapability,
            "qeaj75wk3HF4DwQ8qbIi7g", // DeviceSupportsEnhancedMultitasking
        ]
        
        return Binding(get: {
            if let value = cache_extra[keys.first!] as? Int? {
                return value == 1
            }
            
            return false
        }, set: { enabled in
            if enabled {
                Alertinator.shared.alert(title: "安全警告！", body: "这是一个高风险的修改项！如果您的设备设置了字母数字混合锁屏密码，请绝对不要开启此选项！请务必不要关闭‘在台前调度中显示程序坞’，否则设备横屏旋转时将导致 Bootloop（无限重启）！此外，部分用户反馈在开启 iPadOS UI 并点击台前调度后可能进入恢复模式。请谨慎评估风险后操作。")
            }
            
            cache_data.mutableBytes.storeBytes(of: enabled ? 3 : 1, toByteOffset: value_off, as: Int.self)
            
            for key in keys {
                if enabled {
                    cache_extra[key] = 1
                } else {
                    cache_extra.removeObject(forKey: key)
                }
            }
        })
    }
    
    private func mg_region_restrict_binding() -> Binding<Bool> {
        guard let cache_extra = mg_dict_now["CacheExtra"] as? NSMutableDictionary else {
            return .constant(false)
        }
        
        return Binding<Bool>(
            get: {
                return cache_extra["h63QSdBCiT/z0WU6rdQv6Q"] as? String == "US" &&
                    cache_extra["zHeENZu+wbg7PUprwNwBWg"] as? String == "LL/A"
            },
            set: { enabled in
                if enabled {
                    Alertinator.shared.alert(title: "法律与合规提示", body: "请勿利用此功能违反当地法律法规（例如在要求拍照强制发声的地区强行关闭快门声音）。开发者不对任何违规行为承担责任！")
                    cache_extra["h63QSdBCiT/z0WU6rdQv6Q"] = "US"
                    cache_extra["zHeENZu+wbg7PUprwNwBWg"] = "LL/A"
                } else {
                    cache_extra.removeObject(forKey: "h63QSdBCiT/z0WU6rdQv6Q")
                    cache_extra.removeObject(forKey: "zHeENZu+wbg7PUprwNwBWg")
                }
            }
        )
    }
    
    private func mg_internal_binding() -> Binding<Bool> {
        guard let cache_data = mg_dict_now["CacheData"] as? NSMutableData else {
            return .constant(false)
        }
        
        let off_apple_internal_install = cache_data_offset("EqrsVvjcYDdxHBiQmGhAWw")
        let off_has_internal_settings_bundle = cache_data_offset("Oji6HRoPi7rH7HPdWVakuw")
        let off_internal_build = cache_data_offset("LBJfwOEzExRxzlAnSuI7eg")
        
        return Binding(
            get: {
                return cache_data.bytes.load(fromByteOffset: off_apple_internal_install, as: Int.self) == 1
            },
            set: { enabled in
                cache_data.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_apple_internal_install, as: Int.self)
                cache_data.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_has_internal_settings_bundle, as: Int.self)
                cache_data.mutableBytes.storeBytes(of: enabled ? 1 : 0, toByteOffset: off_internal_build, as: Int.self)
            }
        )
    }
    
    private func is_device_good() -> Bool {
        let supported: [String] = ["iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone17,5"]
        
        if supported.contains(machine_name()) && doubleSystemVersion() < 19.0 {
            return true
        }
        
        return false
    }
    
    private func machine_name() -> String {
        var sys_info = utsname()
        uname(&sys_info)
        let machine_mirror = Mirror(reflecting: sys_info.machine)
        
        return machine_mirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    private func mdm_neuter() {
        let targetDir = URL(fileURLWithPath: TweakPaths.mdm_profiles, isDirectory: true)

        let knownFiles = [
            "CloudConfigurationDetails.plist",
            "ClientTruth.plist",
            "CloudConfigurationSetAsideDetails.plist",
            "MDM.plist",
            "MCProfileEvents.plist",
            "MDMEvents.plist",
            "ProfileTruth.plist",
            "MCFeatureOverrides.plist",
            "ProfilePreferences.plist"
        ]

        let emptyPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
"""
        let emptyPlistBytes = Array(emptyPlist.utf8)

        // ── Sandbox Escape: try ALL methods, never give up early ──────────────
        var sbxHandle: Int64 = -99
        var sbxMethod = "无"

        // Method 0: Jailbreak runtime unsandbox (Dopamine / palera1n / generic)
        if let method = jailbreak_unsandbox() {
            sbxHandle = 0; sbxMethod = method
            print("(mdm) jailbreak unsandbox succeeded: \(method)")
        }

        // Method A: sandbox_extension_issue_file (direct syscall, no containermanagerd)
        if sbxHandle < 0 {
            if let token = sandbox_extension_issue_file(path: TweakPaths.mdm_profiles_dir) {
                if let h = sandbox_extension_consume(token), h >= 0 {
                    sbxHandle = h; sbxMethod = "sbx-issue-dir"
                    print("(mdm) sandbox_extension_issue_file+consume succeeded for dir: handle=\(h)")
                }
            }
        }

        // Method B: cmg-activate (container_object_sandbox_extension_activate)
        if sbxHandle < 0 {
            if let _ = grant_mdm_access() {
                sbxHandle = 0; sbxMethod = "cmg-activate"
            }
        }

        // Method C: bad_query with mobilegestaltcache identifier redirect
        if sbxHandle < 0 {
            var path_c = TweakPaths.mdm_profiles_dir.utf8CString.map { Int8($0) }
            var mg_c = "systemgroup.com.apple.mobilegestaltcache".utf8CString.map { Int8($0) }
            sbxHandle = bad_query(&path_c, false, &mg_c, true)
            if sbxHandle >= 0 { sbxMethod = "bad_query-mg" }
        }

        // Method D: bad_query with auto-detected identifier (original path)
        if sbxHandle < 0 {
            var path_c = TweakPaths.mdm_profiles_dir.utf8CString.map { Int8($0) }
            sbxHandle = bad_query(&path_c, false, nil, false)
            if sbxHandle >= 0 { sbxMethod = "bad_query" }
        }

        // Method E: UUID path bypass (key technique for iOS 26.5+)
        var uuidMdmPath: String? = nil
        if sbxHandle < 0 {
            if let containerRoot = resolve_mdm_uuid_path() {
                let uuidTarget = containerRoot.hasSuffix("/")
                    ? containerRoot + "Library/ConfigurationProfiles/"
                    : containerRoot + "/Library/ConfigurationProfiles/"
                uuidMdmPath = uuidTarget
                print("(mdm) trying UUID path bypass: \(uuidTarget)")

                var uuid_c = uuidTarget.utf8CString.map { Int8($0) }
                var mg_c = "systemgroup.com.apple.mobilegestaltcache".utf8CString.map { Int8($0) }
                sbxHandle = bad_query(&uuid_c, false, &mg_c, true)
                if sbxHandle >= 0 {
                    sbxMethod = "bad_query-uuid"
                    print("(mdm) ✓ UUID path bypass succeeded! handle=\(sbxHandle)")
                } else {
                    sbxHandle = bad_query(&uuid_c, false, nil, false)
                    if sbxHandle >= 0 {
                        sbxMethod = "bad_query-uuid-auto"
                        print("(mdm) ✓ UUID path auto-detect succeeded! handle=\(sbxHandle)")
                    }
                }
            }
        }

        if sbxHandle < 0 {
            print("(mdm) all directory-level escapes failed (\(sbxHandle)), will try per-file methods")
        }

        defer {
            if sbxHandle >= 0 && sbxMethod.hasPrefix("bad_query") {
                bad_query_release(sbxHandle)
            }
        }

        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupRoot = documents.appendingPathComponent("SystemFileBackups/MDM", isDirectory: true)
        try? fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        var written  = 0
        var purged   = 0
        var noEntry  = 0
        var permFail = 0
        var lastErr  = ""

        for name in knownFiles {
            let fileURL  = targetDir.appendingPathComponent(name)
            let filePath: String
            if let uuidDir = uuidMdmPath, sbxMethod.contains("uuid") {
                filePath = uuidDir.hasSuffix("/") ? uuidDir + name : uuidDir + "/" + name
            } else {
                filePath = fileURL.path
            }
            var handled  = false

            // Per-file sandbox_extension_issue_file
            if sbxHandle < 0 {
                if let token = sandbox_extension_issue_file(path: filePath) {
                    if let h = sandbox_extension_consume(token), h >= 0 {
                        print("(mdm) per-file sbx-issue succeeded for \(name): handle=\(h)")
                    }
                }
            }

            // Try Darwin.open / write
            let rfd = filePath.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
            if rfd >= 0 {
                let bPath = backupRoot.appendingPathComponent(name).path
                bPath.withCString { bp in
                    let bfd = Darwin.open(bp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o644)
                    if bfd >= 0 {
                        var buf = [UInt8](repeating: 0, count: 8192); var n: Int
                        repeat { n = Darwin.read(rfd, &buf, buf.count); if n > 0 { _ = Darwin.write(bfd, buf, n) } } while n > 0
                        Darwin.close(bfd)
                    }
                }
                Darwin.close(rfd)
                let wfd = filePath.withCString { Darwin.open($0, O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW) }
                if wfd >= 0 {
                    let ok = emptyPlistBytes.withUnsafeBytes { ptr in
                        Darwin.write(wfd, ptr.baseAddress!, emptyPlistBytes.count) == emptyPlistBytes.count
                    }
                    Darwin.close(wfd)
                    if ok { written += 1; handled = true; print("(mdm) ✓ overwrite \(name)") }
                    else { lastErr = String(cString: strerror(errno)); print("(mdm) write() \(name): \(lastErr)") }
                } else {
                    lastErr = String(cString: strerror(errno)); print("(mdm) open(WRONLY) \(name): \(lastErr)")
                }
            } else {
                let e = errno
                if e == ENOENT {
                    noEntry += 1; handled = true
                    print("(mdm) \(name) ENOENT (not enrolled)")
                } else {
                    lastErr = String(cString: strerror(e))
                    print("(mdm) open(RDONLY) \(name): \(lastErr) (\(e))")
                }
            }

            if handled { continue }

            // Method: BackgroundAssets Purge (ba_purge_file)
            if ba_purge_file(url: fileURL) {
                purged += 1
                handled = true
                print("(mdm) ✓ ba_purge succeeded for \(name)")
                continue
            }

            permFail += 1
            print("(mdm) all methods denied for \(name): \(lastErr)")
        }

        let total = written + purged
        let escInfo = sbxHandle >= 0 ? sbxMethod : "无(\(sbxHandle))"

        mdm_backup_exists = has_mdm_backups()

        if total > 0 {
            Alertinator.shared.alert(
                title: "MDM 已成功绕过！",
                body: "\(total) 个 MDM 描述文件已覆盖为空字典。\n" +
                      "逃逸方式: \(escInfo)。\(noEntry) 个文件未预置。\n" +
                      "安全备份位于 Documents/SystemFileBackups/MDM。\n请重启设备以使配置彻底生效。"
            )
        } else if noEntry == knownFiles.count {
            Alertinator.shared.alert(
                title: "未加入 MDM 监管",
                body: "在 ConfigurationProfiles 目录下未检测到任何 MDM 描述文件。\n" +
                      "您的设备当前未受企业或学校 MDM 监管。"
            )
        } else {
            Alertinator.shared.alert(
                title: "MDM 绕过失败",
                body: "逃逸方式: \(escInfo)。\(permFail) 个文件访问被拒绝。\n" +
                      "\(noEntry) 个文件未找到。最后系统错误: \(lastErr.isEmpty ? "未知" : lastErr)。\n" +
                      "系统版本: iOS \(ProcessInfo.processInfo.operatingSystemVersionString)。\n\n" +
                      "越狱状态: \(is_jailbroken() ? "已越狱" : "未越狱")。\n" +
                      "提示：若在纯非越狱环境下使用普通自签名 IPA，系统沙盒策略可能拦截该路径。建议通过 TrollStore 安装或在越狱环境下运行。"
            )
        }
    }

    private func mdm_restore_action() {
        // ── 沙盒逃逸：复用 mdm_neuter 的多层兜底链 ──
        var escaped = false

        // Method 0: Jailbreak runtime unsandbox
        if let _ = jailbreak_unsandbox() { escaped = true }

        // Method A: sandbox_extension_issue_file (direct)
        if !escaped {
            if let token = sandbox_extension_issue_file(path: TweakPaths.mdm_profiles_dir) {
                if let h = sandbox_extension_consume(token), h >= 0 { escaped = true }
            }
        }

        // Method B: cmg-activate
        if !escaped {
            if let _ = grant_mdm_access() { escaped = true }
        }

        // Method C: bad_query with mobilegestaltcache redirect
        if !escaped {
            var path_c = TweakPaths.mdm_profiles_dir.utf8CString.map { Int8($0) }
            var mg_c = "systemgroup.com.apple.mobilegestaltcache".utf8CString.map { Int8($0) }
            let h = bad_query(&path_c, false, &mg_c, true)
            if h >= 0 { escaped = true; bad_query_release(h) }
        }

        // Method D: bad_query auto-detect
        if !escaped {
            var path_c = TweakPaths.mdm_profiles_dir.utf8CString.map { Int8($0) }
            let h = bad_query(&path_c, false, nil, false)
            if h >= 0 { escaped = true; bad_query_release(h) }
        }

        // Method E: UUID path bypass
        if !escaped {
            if let containerRoot = resolve_mdm_uuid_path() {
                let uuidTarget = containerRoot.hasSuffix("/")
                    ? containerRoot + "Library/ConfigurationProfiles/"
                    : containerRoot + "/Library/ConfigurationProfiles/"
                var uuid_c = uuidTarget.utf8CString.map { Int8($0) }
                var mg_c = "systemgroup.com.apple.mobilegestaltcache".utf8CString.map { Int8($0) }
                let h = bad_query(&uuid_c, false, &mg_c, true)
                if h >= 0 { escaped = true; bad_query_release(h) }
            }
        }

        if !escaped {
            Alertinator.shared.alert(
                title: "MDM 还原失败",
                body: "无法获取 ConfigurationProfiles 目录的写入权限。所有沙盒逃逸方式均失败。\n" +
                      "越狱状态: \(is_jailbroken() ? "已越狱" : "未越狱")。\n" +
                      "建议通过 TrollStore 安装或在越狱环境下运行。"
            )
            return
        }

        let result = restore_mdm_backups()
        if result.restored > 0 {
            Alertinator.shared.alert(
                title: "MDM 描述文件还原成功！",
                body: "已成功从备份还原 \(result.restored) 个 MDM 配置文件。\n请重启设备以使原配置生效。"
            )
        } else {
            Alertinator.shared.alert(
                title: "MDM 描述文件还原失败",
                body: "已获取写入权限，但文件写入失败。错误: \(result.error ?? "未知错误")"
            )
        }
    }
}
