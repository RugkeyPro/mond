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
                        Label("File Browser", systemImage: "folder")
                    }
                } header: {
                    Label("Files", systemImage: "internaldrive")
                } footer: {
                    Text("Browse mond's container or verify precise /private/var paths; managed writes require an explicit per-target check.")
                }

                Section {
                    NavigationLink {
                        FileBrowserView(root: BrowserRoot(
                            title: "MDM Configuration Profiles",
                            subtitle: "MDM profile storage used by Apple Business/School Manager",
                            icon: "shield.lefthalf.filled",
                            url: URL(fileURLWithPath: TweakPaths.mdm_profiles, isDirectory: true),
                            mode: .systemManaged
                        ))
                    } label: {
                        Label("MDM Profiles", systemImage: "shield.lefthalf.filled")
                    }

                    Button {
                        mdm_neuter()
                    } label: {
                        Label("Bypass MDM (Overwrite Profiles with Empty Dict)", systemImage: "shield.slash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Label("MDM Management", systemImage: "lock.shield")
                } footer: {
                    Text("Instead of deleting files (which causes daemon auto-recovery), 'Bypass MDM' overwrites profile files with empty payloads. Safety backups are created before changes. Reboot required afterwards.")
                }

                if !mg_valid || mg_empty {
                    Section {
                        if mg_empty {
                            PlainAlert(title: "Do not reboot!", icon: "exclamationmark.triangle.fill", text: "Your MobileGestalt.plist seems to be empty.", color: Color.yellow)
                        }
                        
                        if !mg_valid {
                            PlainAlert(title: "Do not reboot!", icon: "exclamationmark.triangle.fill", text: "Your MobileGestalt.plist seems to be invalid.", color: Color.yellow)
                        }
                    } header: {
                        Label("Warning", systemImage: "exclamationmark.triangle")
                    } footer: {
                        Text("Rebooting now might cause a bootloop. Try pressing 'Revert Tweaks'. If the warnings dont go away after that, you're fucked.")
                    }
                }
                
                Section {
                    Button {
                        mg_apply()
                    } label: {
                        Text("Apply Tweaks")
                    }
                    
                    Button {
                        mg_revert()
                    } label: {
                        Text("Revert Tweaks")
                    }
                } footer: {
                    Text("**WARNING:** These tweaks have the capability to break features on your device or softbrick it if misused!")
                }
                
                Section {
                    Picker(selection: $selected_st) {
                        Text("Original (\(og_st))").tag("og")
                        
                        if is_device_good() {
                            Text("Disable Dynamic Island").tag("no_dynamic_island")
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
                            Text("iPhone X Gestures").tag("x")
                        }
                    } label: {
                        HStack {
                            Text("Subtype")
                            Spacer()
                        }
                    }
                    
                    Toggle("Custom Device Name", isOn: $enable_devicename)
                    
                    if enable_devicename {
                        TextField("Device Name", text: $mg_devicename)
                    }
                } header: {
                    Label("Device Artwork", systemImage: "paintbrush.pointed")
                }
                
                // basic tweak toggles
                Section {
                    PlainToggle(text: "Dynamic Island", minSupportedVersion: 19.0, isOn: mg_key_binding(["YlEtTtHlNesRBMal1CqRaA"]))
                    PlainToggle(text: "Always On Display", minSupportedVersion: 18.0, isOn: mg_key_binding(["j8/Omm6s1lsmTDFsXjsBfA", "2OOJf1VhaM7NxfRok3HbWQ"]))
                    PlainToggle(text: "AOD Vibrancy", minSupportedVersion: 18.0, isOn: mg_key_binding(["ykpu7qyhqFweVMKtxNylWA"]))
                    PlainToggle(text: "Charge Limit", minSupportedVersion: 17.0, isOn: mg_key_binding(["37NVydb//GP/GrhuTN+exg"]))
                    PlainToggle(text: "Boot Chime", isOn: mg_key_binding(["QHxt+hGLaBPbQJbXiUJX3w"]))
                    PlainToggle(text: "Liquid Glass LPM", minSupportedVersion: 19.0, isOn: mg_key_binding(["SAGvsp6O6kAQ4fEfDJpC4Q"]))
                } header: {
                    Label("Software-Oriented Features", systemImage: "gearshape")
                }
                
                Section {
                    PlainToggle(text: "Camera Control", minSupportedVersion: 18.0, isOn: mg_key_binding(["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"]))
                    PlainToggle(text: "Action Button", minSupportedVersion: 17.0, isOn: mg_key_binding(["cT44WE1EohiwRzhsZ8xEsw"]))
                    PlainToggle(text: "Crash Detection", isOn: mg_key_binding(["HCzWusHQwZDea6nNhaKndw"]))
                    if hasHomeButton() {
                        PlainToggle(text: "Enable Tap to Wake", isOn: mg_key_binding(["yZf3GTRMGTuwSV/lD7Cagw"]))
                    }
                    PlainToggle(text: "Pulse Width Modulation", minSupportedVersion: 19.0, isOn: mg_key_binding(["6IejgN+1Fmu5/QrZFOIeNw"]))
                } header: {
                    Label("Hardware-Oriented Features", systemImage: "iphone")
                }
                
                Section {
                    PlainToggle(text: "Security Research Device UI", minSupportedVersion: 26.0, isOn: mg_key_binding(["XYlJKKkj2hztRP1NWWnhlw"]))
                    
                    PlainToggle(
                        text: "Disable Region Restrictions",
                        infoType: .info,
                        infoMessage: "This tweak may be broken or have no effect on some iOS versions or devices.",
                        isOn: mg_region_restrict_binding()
                    )
                    
                    PlainToggle(
                        text: "Apple Intelligence",
                        infoType: .info,
                        infoMessage: "Apple Intelligence activation is currently broken and may not work.",
                        minSupportedVersion: 18.1,
                        isOn: mg_key_binding(["A62OafQ85EJAiiqKn4agtg"])
                    )
                    
                    HStack(spacing: 10) {
                        Picker("Spoofing", selection: $product_type) {
                            Text("Default").tag(machine_name())
                            if UIDevice.current.userInterfaceIdiom == .pad {
                                if doubleSystemVersion() >= 17.4 {
                                    Text("iPad Pro 11-inch (M4)").tag("iPad16,3")
                                    Text("iPad Pro 11-inch (M4, Cellular)").tag("iPad16,4")
                                }
                                Text("iPad Pro 11-inch (4th Gen)").tag("iPad14,3")
                                Text("iPad Pro 11-inch (4th Gen, Cellular)").tag("iPad14,4")
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
                                title: "Device Spoofing Info",
                                body: "Only spoof your device model if you want to download Apple Intelligence. This may break Face ID. If you decide to unspoof and want to keep Apple Intelligence, do NOT re-enter the Apple Intelligence & Siri menu in Settings."
                            )
                        } label: {
                            Image(systemName: "info.circle")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label("Eligibility", systemImage: "checklist")
                }
                
                Section {
                    let cache_extra = mg_dict_now["CacheExtra"] as? NSMutableDictionary
                    
                    PlainToggle(text: "Allow Installing iPadOS Apps", isOn: mg_key_binding(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, default_val: [1], on_val: [1, 2]))
                    PlainToggle(text: "Apple Pencil Settings", isOn: mg_key_binding(["yhHcB0iH0d1XzPO/CFd3ow"]))
                    
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        PlainToggle(text: "Stage Manager", isOn: mg_key_binding(["qeaj75wk3HF4DwQ8qbIi7g"]))
                    }
                    PlainToggle(
                        text: "iPadOS UI",
                        infoType: .warning,
                        infoMessage: "This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! Some users have also reported that enabling the iPadOS UI and then tapping Stage Manager can cause the device to enter Recovery Mode, even when the UI itself appears unchanged. The Settings search bar may move to the top before this happens. With these three things in mind, you may experience general instability, or other major issues such as app data randomly disappearing. But I guess some funny multitasking features that still make the device relatively unusable are cool? Whatever dude, I'm not here to tell you how to use your own device.",
                        isOn: mg_trollpad_binding()
                    )
                    .disabled(cache_extra?["+3Uf0Pm5F8Xy7Onyvko0vA"] as? String != "iPhone")
                } header: {
                    Label("iPadOS Features", systemImage: "ipad")
                }
                
                Section {
                    PlainToggle(text: "Internal Storage", isOn: mg_key_binding(["LBJfwOEzExRxzlAnSuI7eg"]))
                    PlainToggle(text: "Internal Features", isOn: mg_internal_binding())
                    PlainToggle(text: "Metal HUD in All Apps", isOn: mg_key_binding(["EqrsVvjcYDdxHBiQmGhAWw"]))
                } header: {
                    Label("Internal", systemImage: "ant")
                }
            }
            .navigationTitle("mond")
            .tint(Color("AccentColor"))
            .onAppear {
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
                return "Failed to get ArtworkDeviceSubType!"
            case .missingArtworkDeviceName:
                return "Failed to get ArtworkDeviceProductDescription!"
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
            Alertinator.shared.alert(title: "Failed to load current MobileGestalt!", body: "Restart the app and try again. Check logs for more detailed information.")
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
            Alertinator.shared.alert(title: "Successfully applied Gestalt tweaks!", body: "Respring your device for changes to take effect. Note that some tweaks may require a reboot for them to apply properly.", actionLabel: "Respring", action: {
                state.respring()
            })
        } catch {
            print("(mg) failed to apply mobilegestalt: \(error)")
            Alertinator.shared.alert(title: "Failed to apply MobileGestalt!", body: "Restart the app and try again. Check logs for more detailed information.")
        }
    }
    
    private func mg_revert() {
        do {
            let backup_url = URL(fileURLWithPath: AppPaths.backups).appendingPathComponent("SavedGestalt.plist")
            let backup_data = try Data(contentsOf: backup_url)
            try mg_write(backup_data)

            print("(mg) successfully reverted mobilegestalt!)")
            Alertinator.shared.alert(title: "Successfully reverted Gestalt tweaks!", body: "Reboot your device for changes to take effect.")
        } catch {
            // The direct file write path now surfaces the underlying error through the catch.
            print("(mg) failed to revert mobilegestalt: \(error)")
            Alertinator.shared.alert(title: "Failed to revert MobileGestalt!", body: "Check logs for error information.")
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
                // if it exists inside of the plist, then update it. if not then pull the value completely.
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
                Alertinator.shared.alert(title: "Warning!", body: "This is a very dangerous tweak to use! If you use an alphanumeric passcode, DO NOT USE THIS TWEAK AT ALL! Please do not turn off \"Show Dock In Stage Manager\" or your device will BOOTLOOP when rotating to landscape! With these two things in mind, you may experience general instability, or other major issues such as app data randomly disappearing. I'm honestly not too certain why you'd want to use this tweak anyways, it's not like your device is gonna be all that usable (due to apps scaling weirdly) when it's enabled.")
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
                    Alertinator.shared.alert(title: "Warning!", body: "Please do not use this feature to bypass region restrictions that would equate to breaking regional laws (e.g. disabling the camera shutter sound). We will NOT be held responsible for enabling any illegal activites!")
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
            "ProfileTruth.plist"
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
        var sbxMethod = "none"

        // Method 0: Jailbreak runtime unsandbox (Dopamine / palera1n / generic)
        // This dynamically removes sandbox restrictions via jailbreak daemon APIs.
        // No entitlements or signing tool changes needed — works with 万能签名.
        if let method = jailbreak_unsandbox() {
            sbxHandle = 0; sbxMethod = method
            print("(mdm) jailbreak unsandbox succeeded: \(method)")
        }

        // Method A: sandbox_extension_issue_file (direct syscall, no containermanagerd)
        // On AMFI-patched jailbreaks this issues a token for ANY path
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
        // The kernel blacklist checks for "configurationprofiles" in the path/identifier.
        // We resolve the container to its UUID path (e.g. /.../<UUID>/Library/ConfigurationProfiles)
        // which does NOT contain "configurationprofiles" in the SystemGroup directory name.
        // Then we use mobilegestaltcache (allowed identifier) + path traversal to the UUID path.
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
                    // Also try without explicit group (let bad_query use fallback logic)
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
            // If UUID bypass succeeded, use UUID-based path for file access
            // (sandbox token covers UUID path, not the named symlink path)
            let filePath: String
            if let uuidDir = uuidMdmPath, sbxMethod.contains("uuid") {
                filePath = uuidDir.hasSuffix("/") ? uuidDir + name : uuidDir + "/" + name
            } else {
                filePath = fileURL.path
            }
            var handled  = false

            // ── Per-file sandbox_extension_issue_file ──────────────────────────
            // If directory-level escape failed, try issuing a token per file
            if sbxHandle < 0 {
                if let token = sandbox_extension_issue_file(path: filePath) {
                    if let h = sandbox_extension_consume(token), h >= 0 {
                        print("(mdm) per-file sbx-issue succeeded for \(name): handle=\(h)")
                    }
                }
            }

            // ── Try Darwin.open / write ────────────────────────────────────────
            let rfd = filePath.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
            if rfd >= 0 {
                // File exists — backup via raw fd copy
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

            // ── Method: BackgroundAssets Purge (ba_purge_file) ───────────────
            // Uses LaunchServices _LSRegisterURL + backgroundassetsd markPurgeable
            // as extracted from BASandboxEscape.ipa.
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
        let escInfo = sbxHandle >= 0 ? sbxMethod : "none(\(sbxHandle))"

        if total > 0 {
            Alertinator.shared.alert(
                title: "MDM Bypassed!",
                body: "\(total) MDM file(s) overwritten with empty dicts. " +
                      "Escape: \(escInfo). \(noEntry) files absent. " +
                      "Backups at Documents/SystemFileBackups/MDM. Reboot required."
            )
        } else if noEntry == knownFiles.count {
            Alertinator.shared.alert(
                title: "Not Enrolled in MDM",
                body: "None of the \(knownFiles.count) MDM profile files exist in ConfigurationProfiles. " +
                      "Your device is not currently enrolled in MDM."
            )
        } else {
            Alertinator.shared.alert(
                title: "MDM Bypass Failed",
                body: "Escape: \(escInfo). Access denied for \(permFail) file(s). " +
                      "\(noEntry) not found. Last error: \(lastErr.isEmpty ? "unknown" : lastErr). " +
                      "iOS \(ProcessInfo.processInfo.operatingSystemVersionString).\n\n" +
                      "Jailbreak detected: \(is_jailbroken() ? "Yes" : "No"). " +
                      "This feature requires a jailbreak (Dopamine/palera1n) " +
                      "or install via TrollStore. 万能签名 cannot grant sandbox escape privileges."
            )
        }
    }
}

