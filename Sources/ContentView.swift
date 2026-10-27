import SwiftUI
import PhotosUI
import UIKit

struct Patch: Identifiable {
    var id = UUID()
    var rect: CGRect = .zero      // 图片像素坐标（左上原点）
    var text: String = ""
    var fontSize: CGFloat = 42    // 像素字号（导出时按 scale 换算成 pt）
    var color: Color = .black
    var weightIndex: Int = 3      // 0细 1常规 2中等 3半粗 4粗
    var letterSpacing: CGFloat = 0
    var fitWidth: Bool = true
    var bgColor: Color = .white
}

let weightNames = ["细", "常规", "中等", "半粗", "粗"]
let uiWeights: [UIFont.Weight] = [.light, .regular, .medium, .semibold, .bold]
let fontWeights: [Font.Weight] = [.light, .regular, .medium, .semibold, .bold]

struct PixelBuffer {
    let data: [UInt8]
    let w: Int
    let h: Int
    let bytesPerRow: Int
    let bytesPerPixel: Int
    let isBGR: Bool

    func rgb(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let idx = y * bytesPerRow + x * bytesPerPixel
        if isBGR {
            return (data[idx + 2], data[idx + 1], data[idx])
        }
        return (data[idx], data[idx + 1], data[idx + 2])
    }
}

func makePixelBuffer(_ cg: CGImage) -> PixelBuffer? {
    let w = cg.width
    let h = cg.height
    let bpp = cg.bitsPerPixel / 8
    guard bpp == 3 || bpp == 4 else { return nil }
    guard let provider = cg.dataProvider, let cf = provider.data else { return nil }
    let count = CFDataGetLength(cf)
    guard let ptr = CFDataGetBytePtr(cf) else { return nil }
    let data = [UInt8](UnsafeBufferPointer(start: ptr, count: count))
    let isBGR = cg.bitmapInfo.contains(.byteOrder32Little)
    return PixelBuffer(data: data, w: w, h: h, bytesPerRow: cg.bytesPerRow, bytesPerPixel: bpp, isBGR: isBGR)
}

func inferScale(_ width: Int) -> CGFloat {
    if width >= 1170 && width <= 1320 && width % 3 == 0 { return 3 }
    if width >= 800 && width <= 900 && width % 2 == 0 { return 2 }
    return 1
}

struct ContentView: View {
    @State private var image: UIImage?
    @State private var imageItem: PhotosPickerItem?
    @State private var patches: [Patch] = []
    @State private var selectedID: UUID?
    @State private var drawMode = false
    @State private var dragStart: CGPoint?
    @State private var dragRect: CGRect?
    @State private var showSavedAlert = false

    private var pixelW: Int { image?.cgImage?.width ?? 0 }
    private var pixelH: Int { image?.cgImage?.height ?? 0 }
    private var dispW: CGFloat { UIScreen.main.bounds.width }
    private var dispH: CGFloat {
        guard pixelW > 0, pixelH > 0 else { return 0 }
        return dispW * CGFloat(pixelH) / CGFloat(pixelW)
    }
    private var s: CGFloat { pixelW > 0 ? dispW / CGFloat(pixelW) : 1 }

    private var selectedIndex: Int? {
        patches.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if image != nil {
                    ScrollView([.vertical, .horizontal]) {
                        canvas
                    }
                    .background(Color.black)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("点击右上角「选择图片」\n打开一张截图")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
                controlPanel
            }
            .navigationTitle("改数字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    PhotosPicker(selection: $imageItem, matching: .images, photoLibrary: .shared()) {
                        Label("选择图片", systemImage: "photo")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("导出") { exportAndSave() }
                        .disabled(image == nil)
                }
            }
            .onChange(of: imageItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        await MainActor.run {
                            image = ui
                            setupPresets()
                        }
                    }
                }
            }
            .alert("已保存", isPresented: $showSavedAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("修改后的图片已保存到相册")
            }
        }
    }

    // MARK: - 画布

    private var canvas: some View {
        ZStack {
            Image(uiImage: image!)
                .resizable()
                .scaledToFit()
                .frame(width: dispW, height: dispH)

            ForEach(patches) { p in
                patchOverlay(p)
            }

            if drawMode, let r = dragRect {
                Rectangle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: r.width * s, height: r.height * s)
                    .position(x: r.midX * s, y: r.midY * s)
            }
        }
        .frame(width: dispW, height: dispH)
        .contentShape(Rectangle())
        .gesture(dragGesture, including: drawMode ? .gesture : .none)
        .simultaneousGesture(tapGesture, including: drawMode ? .none : .gesture)
    }

    private func patchOverlay(_ p: Patch) -> some View {
        ZStack {
            Rectangle()
                .fill(p.bgColor)
                .frame(width: p.rect.width * s, height: p.rect.height * s)
            Text(p.text.isEmpty ? " " : p.text)
                .font(.system(size: p.fontSize * s, weight: fontWeights[p.weightIndex]))
                .foregroundColor(p.color)
                .kerning(p.letterSpacing * s)
                .lineLimit(1)
                .minimumScaleFactor(0.2)
            Rectangle()
                .stroke(p.id == selectedID ? Color.blue : Color.red, lineWidth: 2)
        }
        .frame(width: p.rect.width * s, height: p.rect.height * s)
        .position(x: p.rect.midX * s, y: p.rect.midY * s)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard drawMode else { return }
                if dragStart == nil { dragStart = value.startLocation }
                let a = dragStart!
                let b = value.location
                dragRect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                  width: abs(b.x - a.x), height: abs(b.y - a.y))
            }
            .onEnded { _ in
                defer { dragStart = nil; dragRect = nil }
                guard drawMode, let r = dragRect, r.width > 8, r.height > 8 else { return }
                let pr = CGRect(x: r.origin.x / s, y: r.origin.y / s,
                                width: r.width / s, height: r.height / s)
                let newPatch = Patch(rect: pr,
                                     text: "",
                                     fontSize: max(10, pr.height / 0.727),
                                     color: sampleTextColor(pr),
                                     weightIndex: 3,
                                     letterSpacing: 0,
                                     fitWidth: true,
                                     bgColor: sampleBgColor(pr))
                patches.append(newPatch)
                selectedID = newPatch.id
                drawMode = false
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let px = value.location.x / s
                let py = value.location.y / s
                if let hit = patches.last(where: { $0.rect.contains(CGPoint(x: px, y: py)) }) {
                    selectedID = hit.id
                } else {
                    selectedID = nil
                }
            }
    }

    // MARK: - 像素采样

    private func sampleBgColor(_ r: CGRect) -> Color {
        guard let cg = image?.cgImage, let buf = makePixelBuffer(cg) else { return .white }
        let band = max(2, buf.w / 500)
        let x0 = max(0, Int(r.minX) - band), y0 = max(0, Int(r.minY) - band)
        let x1 = min(buf.w - 1, Int(r.maxX) + band), y1 = min(buf.h - 1, Int(r.maxY) + band)
        var cols: [[Int]] = []
        var x = x0
        while x <= x1 {
            cols.append([Int(buf.rgb(x, y0).r), Int(buf.rgb(x, y0).g), Int(buf.rgb(x, y0).b)])
            cols.append([Int(buf.rgb(x, y1).r), Int(buf.rgb(x, y1).g), Int(buf.rgb(x, y1).b)])
            x += band
        }
        var y = y0
        while y <= y1 {
            cols.append([Int(buf.rgb(x0, y).r), Int(buf.rgb(x0, y).g), Int(buf.rgb(x0, y).b)])
            cols.append([Int(buf.rgb(x1, y).r), Int(buf.rgb(x1, y).g), Int(buf.rgb(x1, y).b)])
            y += band
        }
        guard !cols.isEmpty else { return .white }
        cols.sort { $0[0] + $0[1] + $0[2] < $1[0] + $1[1] + $1[2] }
        let m = cols[cols.count / 2]
        return Color(red: Double(m[0]) / 255.0, green: Double(m[1]) / 255.0, blue: Double(m[2]) / 255.0)
    }

    private func sampleTextColor(_ r: CGRect) -> Color {
        guard let cg = image?.cgImage, let buf = makePixelBuffer(cg) else { return .black }
        let x0 = max(0, Int(r.minX)), y0 = max(0, Int(r.minY))
        let x1 = min(buf.w - 1, Int(r.maxX)), y1 = min(buf.h - 1, Int(r.maxY))
        var lums: [(Int, UInt8, UInt8, UInt8)] = []
        for y in y0...y1 {
            for x in x0...x1 {
                let c = buf.rgb(x, y)
                let lum = Int(0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b))
                lums.append((lum, c.r, c.g, c.b))
            }
        }
        guard !lums.isEmpty else { return .black }
        lums.sort { $0.0 < $1.0 }
        let darkest = lums.prefix(max(1, lums.count / 3))
        let n = darkest.count
        let sr = darkest.reduce(0) { $0 + Int($1.1) } / n
        let sg = darkest.reduce(0) { $0 + Int($1.2) } / n
        let sb = darkest.reduce(0) { $0 + Int($1.3) } / n
        return Color(red: Double(sr) / 255.0, green: Double(sg) / 255.0, blue: Double(sb) / 255.0)
    }

    // MARK: - 预设（针对本截图 1320x2868，按宽度等比缩放）

    private func setupPresets() {
        guard let cg = image?.cgImage else { return }
        let W = CGFloat(cg.width)
        let k = W / 1320.0
        patches = [
            Patch(rect: CGRect(x: 400 * k, y: 570 * k, width: 60 * k, height: 40 * k),
                  text: "",
                  fontSize: 42 * k,
                  color: Color(red: 143.0 / 255.0, green: 143.0 / 255.0, blue: 143.0 / 255.0),
                  weightIndex: 2,
                  letterSpacing: 0,
                  fitWidth: true,
                  bgColor: .white),
            Patch(rect: CGRect(x: 525 * k, y: 1237 * k, width: 80 * k, height: 50 * k),
                  text: "",
                  fontSize: 59 * k,
                  color: .black,
                  weightIndex: 3,
                  letterSpacing: 0,
                  fitWidth: true,
                  bgColor: .white)
        ]
        selectedID = patches[0].id
    }

    // MARK: - 控制面板

    private var controlPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    guard image != nil else { return }
                    drawMode.toggle()
                } label: {
                    Label(drawMode ? "框选取消" : "框选数字", systemImage: "rectangle.dashed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(drawMode ? .orange : .blue)

                Button {
                    guard let idx = selectedIndex else { return }
                    let p = patches[idx]
                    var copy = p
                    copy.id = UUID()
                    patches.append(copy)
                    selectedID = copy.id
                } label: {
                    Label("复制", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(selectedIndex == nil)
            }
            .padding(.horizontal)

            if let idx = selectedIndex {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("新数字").frame(width: 56, alignment: .leading)
                            TextField("如 9999", text: binding(idx, \.text))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                        HStack {
                            Text("字号").frame(width: 56, alignment: .leading)
                            Slider(value: binding(idx, \.fontSize), in: 6...200)
                            Text("\(Int(patches[idx].fontSize))").frame(width: 40)
                        }
                        HStack {
                            Text("字距").frame(width: 56, alignment: .leading)
                            Slider(value: binding(idx, \.letterSpacing), in: -10...40)
                            Text("\(Int(patches[idx].letterSpacing))").frame(width: 40)
                        }
                        Picker("粗细", selection: binding(idx, \.weightIndex)) {
                            ForEach(0..<5, id: \.self) { i in
                                Text(weightNames[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        ColorPicker("文字颜色", selection: binding(idx, \.color))
                        ColorPicker("遮盖背景色", selection: binding(idx, \.bgColor))
                        Toggle("自动缩到框内", isOn: binding(idx, \.fitWidth))
                        HStack {
                            Text("x").frame(width: 20)
                            Slider(value: binding(idx, \.rect.origin.x), in: 0...CGFloat(max(pixelW, 1)))
                            Text("\(Int(patches[idx].rect.minX))").frame(width: 44)
                        }
                        HStack {
                            Text("y").frame(width: 20)
                            Slider(value: binding(idx, \.rect.origin.y), in: 0...CGFloat(max(pixelH, 1)))
                            Text("\(Int(patches[idx].rect.minY))").frame(width: 44)
                        }
                        HStack {
                            Text("宽").frame(width: 20)
                            Slider(value: binding(idx, \.rect.size.width), in: 4...CGFloat(max(pixelW, 4)))
                            Text("\(Int(patches[idx].rect.width))").frame(width: 44)
                        }
                        HStack {
                            Text("高").frame(width: 20)
                            Slider(value: binding(idx, \.rect.size.height), in: 4...CGFloat(max(pixelH, 4)))
                            Text("\(Int(patches[idx].rect.height))").frame(width: 44)
                        }
                        Button(role: .destructive) {
                            patches.remove(at: idx)
                            selectedID = nil
                        } label: {
                            Label("删除此修改点", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            } else {
                Text("点「框选数字」后在图上拖一个框，或直接点选已有的红色框")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - 导出

    private func exportAndSave() {
        guard let out = exportImage() else { return }
        UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
        showSavedAlert = true
    }

    private func exportImage() -> UIImage? {
        guard let image, let cg = image.cgImage else { return nil }
        let W = cg.width
        let H = cg.height
        let scale = inferScale(W)
        let ptSize = CGSize(width: CGFloat(W) / scale, height: CGFloat(H) / scale)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: ptSize, format: fmt)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: ptSize))

            for p in patches where !p.text.isEmpty {
                let r = CGRect(x: p.rect.origin.x / scale, y: p.rect.origin.y / scale,
                               width: p.rect.width / scale, height: p.rect.height / scale)
                UIColor(p.bgColor).setFill()
                UIRectFill(r)

                let fs = p.fontSize / scale
                var font = UIFont.systemFont(ofSize: fs, weight: uiWeights[p.weightIndex])
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(p.color)
                ]
                if p.letterSpacing != 0 {
                    attrs[.kern] = p.letterSpacing / scale
                }
                var str = NSAttributedString(string: p.text, attributes: attrs)
                var sizeT = str.size()

                if p.fitWidth && sizeT.width > r.width - 2 {
                    let newFs = fs * (r.width - 2) / sizeT.width
                    font = UIFont.systemFont(ofSize: newFs, weight: uiWeights[p.weightIndex])
                    attrs[.font] = font
                    str = NSAttributedString(string: p.text, attributes: attrs)
                    sizeT = str.size()
                }

                let origin = CGPoint(x: r.midX - sizeT.width / 2,
                                     y: r.midY - sizeT.height / 2)
                str.draw(at: origin)
            }
        }
    }

    // MARK: - 工具

    private func binding<T>(_ idx: Int, _ kp: WritableKeyPath<Patch, T>) -> Binding<T> {
        Binding(
            get: { patches[idx][keyPath: kp] },
            set: { patches[idx][keyPath: kp] = $0 }
        )
    }
}
