import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject private var bleManager = BLEManager()
    @State private var relativeState: Bool = false
    let plotHeight:CGFloat = 175.0
    
    var body: some View {
        let bins = bleManager.powerScale(start: 30, end: 4000.0, points: 51, exponent: 3)
        
        VStack {
            HStack {
                Toggle("Watto", isOn: $bleManager.doScan).font(.title).fontWeight(.heavy)
            }.padding(EdgeInsets(top: 20, leading: 125, bottom: 10, trailing: 125))
            
            Section(header: Text("Current (µA)").fontWeight(.bold)) {
                LinePlot(bleManager: bleManager, data: bleManager.currentData.map {$0 - bleManager.currentOffset})
                    .frame(height: plotHeight)
            }
            
            Section() {
                VStack {
                    HistPlot(data: bleManager.computeHistogram(data: bleManager.currentData.map {$0 - bleManager.currentOffset}, bins: bins), bins: bins)
                        .frame(height: plotHeight - 100)
                        .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
                    CustomXAxisView(bins: bins).fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            HStack {
                VStack {
                    Text("Min (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.minCurrent - bleManager.currentOffset))").font(.title)
                }
                Spacer()
                VStack {
                    Text("Max (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.maxCurrent - bleManager.currentOffset))").font(.title)
                }
                Spacer()
//                VStack {
//                    Text("Power (mW)").font(.footnote)
//                    Text("\(String(format: "%1.1f", bleManager.meanPower))").font(.title)
//                }
                VStack {
                    Text("Avg (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.meanCurrent - bleManager.currentOffset))").font(.title)
                }
                Spacer()
                VStack {
                    Text("Now (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.nowCurrent - bleManager.currentOffset))").font(.title).fontWeight(.heavy)
                }
            }.padding()
            
            Section {
                Toggle("Use Relative Current (median = \(String(format: "%1.0f", bleManager.currentOffset))µA)", isOn: $relativeState)
                    .onChange(of: relativeState) { newValue in
                    bleManager.relativeCurrentChange(to: newValue)
                }
            }.padding()
            
            Section {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.1))
                    
                    VStack {
                        Text("__Battery Life Estimater__: Battery Size (mAh)")
                        Picker("Battery Size", selection: $bleManager.selectedBatterySize) {
                            ForEach(bleManager.batterySizes, id: \.self) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding()
                        
                        Text("\(bleManager.batteryLife)").font(.title2)
                    }
                    .padding()
                }
                .padding(.horizontal)
            }
            
            HStack {
                NonEditableTextEditor(text: $bleManager.debugText)
                    .padding(5)
                    .frame(height: 100)
            }.padding()
            
        }.padding()
    }
}

struct HistPlot: View {
    let data: [Float]
    let bins: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(geometry.size.width / CGFloat(data.count), 1)
            let maxValue = CGFloat(data.max() ?? 1)
            let allZeros = data.allSatisfy { $0 == 0 }
            
            HStack(alignment: .center, spacing: 0) {
                ForEach(data.indices, id: \.self) { index in
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: barWidth, height: allZeros ? 0 : max(CGFloat(data[index]) * geometry.size.height / maxValue, 0))
                    }
                }
            }
        }
    }
}

struct CustomXAxisView: View {
    let bins: [Float]
    let showBins = 10
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                let step = max(bins.count / showBins, 1)
                ForEach(Array(stride(from: 0, to: bins.count, by: step)), id: \.self) { index in
                    Text(customFormatter(value: bins[index]))
                        .frame(width: geometry.size.width / CGFloat(showBins + 1))
                        .rotationEffect(.degrees(90))
                        .foregroundColor(.gray)
                        .font(.footnote)
                    
                    if index != bins.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
    
    func customFormatter(value: Float) -> String {
        if value < 1000 {
            return String(format: "%1.0f", value) // Format the number as it is with one decimal place
        } else {
            let roundedValue = (value / 1000).rounded(.toNearestOrEven) * 1000 // Round the number to the nearest hundred
            let valueInK = roundedValue / 1000 // Convert the number to thousands
            return String(format: "%.1fk", valueInK) // Format the number with one decimal place and append "k"
        }
    }
}

struct LinePlot: View {
    @ObservedObject var bleManager: BLEManager
    let data: [Float]
    var body: some View {
        Chart {
            ForEach(data.indices, id: \.self) { index in
                Plot {
                    LineMark(
                        x: .value("x", index),
                        y: .value("y", Double(data[index]))
                    )
                }
            }
            .foregroundStyle(.red)
        }
        .chartYAxis(.automatic)
        .chartXAxis(.hidden)
        .onTapGesture {
            bleManager.setCollectionMod()
        }
    }
}

extension LinePlot: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let ymin = 0
        let ymax = max(100, data.max() ?? 0)
        
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Index",
            range: Double(0)...Double(data.count - 1),
            gridlinePositions: []
        ) { value in "\(Int(value))" }
        
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Value",
            range: Double(ymin)...Double(ymax),
            gridlinePositions: []
        ) { value in "\(value)" }
        
        let lineSeries = AXDataSeriesDescriptor(
            name: "Data series",
            isContinuous: true,
            dataPoints: data.enumerated().map {
                .init(x: Double($0.offset), y: Double($0.element))
            }
        )
        
        return AXChartDescriptor(
            title: "Data",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [lineSeries]
        )
    }
}

struct NonEditableTextEditor: UIViewRepresentable {
    @Binding var text: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .light)
        textView.isEditable = false
        textView.isSelectable = false
        textView.text = text
        textView.textColor = .green
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}

func simpleMovingAverage(data: [Float], windowSize: Int) -> [Float] {
    var smoothedData: [Float] = []
    
    for i in 0..<data.count {
        let start = max(0, i - windowSize + 1)
        let end = i + 1
        let window = data[start..<end]
        let sum = window.reduce(0, +)
        let average = sum / Float(window.count)
        smoothedData.append(average)
    }
    
    return smoothedData
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
