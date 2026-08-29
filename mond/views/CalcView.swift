
//
//  CalcView.swift
//  mond
//
//  伪装计算器界面。输入 102 后按下 = 进入 mond 主界面。
//  所有普通计算操作均可正常使用，不触发隐藏入口。
//

import SwiftUI

// MARK: - 计算器按键模型

private enum CalcKey: Hashable {
    case digit(String)
    case dot
    case op(String)          // +  −  ×  ÷
    case equals
    case clear               // AC / C
    case negate              // +/−
    case percent             // %
}

// MARK: - 计算器逻辑

private final class CalcEngine: ObservableObject {
    @Published var display: String = "0"

    // ── 隐藏触发 ───────────────────────────────────────────────
    private let secretSequence = "102"
    @Published var unlocked: Bool = false

    // ── 内部状态 ────────────────────────────────────────────────
    private var accumulator: Double = 0
    private var pendingOp: String? = nil
    private var justPressedOp: Bool = false
    private var currentEntry: String = "0"
    private var hasDecimal: Bool = false
    private var needsReset: Bool = false

    // 记录已输入的数字序列（用于密码检测）
    private var digitTrace: String = ""

    var displayValue: Double {
        Double(display) ?? 0
    }

    func press(_ key: CalcKey) {
        switch key {

        // ── 数字 ────────────────────────────────────────────────
        case .digit(let d):
            if needsReset || justPressedOp {
                currentEntry = d
                hasDecimal = false
                needsReset = false
                justPressedOp = false
            } else {
                currentEntry = (currentEntry == "0") ? d : currentEntry + d
            }
            display = currentEntry
            digitTrace += d
            // 超过 6 位就截断前缀，只保留最后 6 位
            if digitTrace.count > 6 { digitTrace = String(digitTrace.suffix(6)) }

        // ── 小数点 ──────────────────────────────────────────────
        case .dot:
            if needsReset || justPressedOp {
                currentEntry = "0."
                needsReset = false
                justPressedOp = false
            } else if !hasDecimal {
                currentEntry += "."
            }
            hasDecimal = true
            display = currentEntry
            digitTrace = "" // 小数点打断密码序列

        // ── 运算符 ──────────────────────────────────────────────
        case .op(let symbol):
            applyPending()
            accumulator = displayValue
            pendingOp = symbol
            justPressedOp = true
            needsReset = false
            digitTrace = "" // 运算符打断密码序列

        // ── 等号 ─────────────────────────────────────────────────
        case .equals:
            // 检测密码：输入序列末尾是 secretSequence
            if digitTrace.hasSuffix(secretSequence) && !unlocked {
                unlocked = true
                return          // 不显示计算结果，直接跳转
            }
            applyPending()
            pendingOp = nil
            justPressedOp = false
            needsReset = true
            digitTrace = ""

        // ── AC / C ───────────────────────────────────────────────
        case .clear:
            accumulator = 0
            pendingOp = nil
            currentEntry = "0"
            display = "0"
            justPressedOp = false
            needsReset = false
            hasDecimal = false
            digitTrace = ""

        // ── 正负切换 ─────────────────────────────────────────────
        case .negate:
            let v = -(displayValue)
            display = format(v)
            currentEntry = display
            digitTrace = ""

        // ── 百分比 ───────────────────────────────────────────────
        case .percent:
            let v = displayValue / 100
            display = format(v)
            currentEntry = display
            digitTrace = ""
        }
    }

    private func applyPending() {
        guard let op = pendingOp else {
            accumulator = displayValue
            return
        }
        let rhs = displayValue
        switch op {
        case "+": accumulator += rhs
        case "−": accumulator -= rhs
        case "×": accumulator *= rhs
        case "÷": accumulator = rhs != 0 ? accumulator / rhs : 0
        default: break
        }
        display = format(accumulator)
        currentEntry = display
        hasDecimal = display.contains(".")
    }

    private func format(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 && !v.isInfinite {
            let i = Int64(exactly: v.rounded()) ?? Int64(v)
            return "\(i)"
        }
        // 最多 8 位有效数字
        let s = String(format: "%.8g", v)
        return s
    }
}

// MARK: - 按键样式

private struct CalcButtonStyle {
    let label: String
    let background: Color
    let foreground: Color
    let isWide: Bool

    static func from(_ key: CalcKey, display: String) -> CalcButtonStyle {
        switch key {
        case .clear:
            let isAC = (display == "0")
            return .init(label: isAC ? "AC" : "C",
                         background: Color(.systemGray3),
                         foreground: .black,
                         isWide: false)
        case .negate:
            return .init(label: "+/−", background: Color(.systemGray3), foreground: .black, isWide: false)
        case .percent:
            return .init(label: "%", background: Color(.systemGray3), foreground: .black, isWide: false)
        case .op(let s):
            return .init(label: s, background: Color.orange, foreground: .white, isWide: false)
        case .equals:
            return .init(label: "=", background: Color.orange, foreground: .white, isWide: false)
        case .digit("0"):
            return .init(label: "0", background: Color(.systemGray5), foreground: .white, isWide: true)
        case .digit(let d):
            return .init(label: d, background: Color(.systemGray5), foreground: .white, isWide: false)
        case .dot:
            return .init(label: ".", background: Color(.systemGray5), foreground: .white, isWide: false)
        }
    }
}

// MARK: - 主视图

struct CalcView: View {
    @StateObject private var engine = CalcEngine()
    @EnvironmentObject var state: AppState

    // 每行按键
    private let rows: [[CalcKey]] = [
        [.clear, .negate, .percent, .op("÷")],
        [.digit("7"), .digit("8"), .digit("9"), .op("×")],
        [.digit("4"), .digit("5"), .digit("6"), .op("−")],
        [.digit("1"), .digit("2"), .digit("3"), .op("+")],
        [.digit("0"), .dot, .equals]
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // ── 显示屏 ─────────────────────────────────
                    HStack {
                        Spacer()
                        Text(engine.display)
                            .font(.system(size: displayFontSize(for: engine.display, width: geo.size.width),
                                          weight: .thin,
                                          design: .default))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }

                    // ── 按键网格 ──────────────────────────────
                    let pad: CGFloat = 12
                    let cols: CGFloat = 4
                    let btnSize = (geo.size.width - pad * (cols + 1)) / cols

                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: pad) {
                            ForEach(row, id: \.self) { key in
                                let style = CalcButtonStyle.from(key, display: engine.display)
                                Button {
                                    engine.press(key)
                                } label: {
                                    Text(style.label)
                                        .font(.system(size: btnSize * 0.36, weight: .regular))
                                        .foregroundColor(style.foreground)
                                        .frame(
                                            width:  style.isWide ? btnSize * 2 + pad : btnSize,
                                            height: btnSize
                                        )
                                        .background(style.background)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, pad)
                        .padding(.bottom, pad)
                    }

                    Spacer(minLength: geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 16)
                }
            }
        }
        // 进入真实 mond 界面
        .fullScreenCover(isPresented: $engine.unlocked) {
            NavigationStack {
                ContentView()
                    .environmentObject(state)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                engine.unlocked = false
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                        }
                    }
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
    }

    // 根据文字长度动态缩小字号
    private func displayFontSize(for text: String, width: CGFloat) -> CGFloat {
        let base: CGFloat = 96
        let chars = CGFloat(text.count)
        if chars <= 7 { return base }
        return max(36, base - (chars - 7) * 10)
    }
}

#Preview {
    CalcView()
        .environmentObject(AppState())
}
