import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject private var bleManager = BLEManager()
    let plotHeight:CGFloat = 175.0
    
    var body: some View {
        VStack {
            HStack {
                Toggle("Watto", isOn: $bleManager.doScan).font(.title).fontWeight(.heavy).onChange(of: bleManager.doScan) { newValue in
                    if newValue {
                        bleManager.dprint("Scanning for Watto")
                    }
                }
            }.padding(EdgeInsets(top: 20, leading: 125, bottom: 10, trailing: 125))
            
            Section(header: Text("Current (µA)").fontWeight(.bold)) {
                ZStack {
                    LinePlot(bleManager: bleManager, data: bleManager.getCurrentData())
                        .frame(height: plotHeight)
                    HStack {
                        Text(String(format: bleManager.plotWindowTime < 60 ? "←%1.1f sec" : "←%1.1f min", bleManager.plotWindowTime < 60 ? bleManager.plotWindowTime : bleManager.plotWindowTime / 60) + " (\(bleManager.modString))")
                            .font(.caption)
                            .offset(y: 15 + plotHeight/2) // Adjust the vertical offset
                            .opacity(0.5)
                        Spacer()
                    }
                }
            }
            
            Section() {
                VStack {
                    HistPlot(data: bleManager.computeHistogram(), bins: bleManager.bins)
                        .frame(height: plotHeight - 100)
                        .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
                             CustomXAxisView(bins: bleManager.bins).fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            HStack {
                VStack {
                    Text("Min (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.minCurrent))").font(.title)
                }
                Spacer()
                VStack {
                    Text("Max (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.maxCurrent))").font(.title)
                }
                Spacer()
//                VStack {
//                    Text("Power (mW)").font(.footnote)
//                    Text("\(String(format: "%1.1f", bleManager.meanPower))").font(.title)
//                }
                VStack {
                    Text("Avg (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.meanCurrent))").font(.title)
                }
                Spacer()
                VStack {
                    Text("Now (µA)").font(.footnote)
                    Text("\(String(format: "%1.0f", bleManager.nowCurrent))").font(.title).fontWeight(.heavy)
                }
            }.padding()
            
            Section {
                HStack {
                    Text("Offset")
                        .font(.headline)
                    Spacer()
                    ZStack {
                        Slider(value: $bleManager.currentOffset, in: 0...1000, onEditingChanged: { editing in
                            if !editing {
                                bleManager.setBins(doReset: true)
                            }
                        })
                        HStack {
                            Spacer()
                            Text("\(bleManager.currentOffset, specifier: "%1.0f")µA")
                                .font(.caption)
                                .offset(y: 10) // Adjust the vertical offset
                        }
                    }
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
                        RoundedRectangle(cornerRadius: 1)
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
        let minY = Double(data.min() ?? 0) * 0.8 // scale to -5% of min value
        let maxY = Double(data.max() ?? 0) * 1.2 // scale to +5% of max value
        let numberOfValues = 5
        
        let stepSize = (maxY - minY) / Double(numberOfValues - 1)
        let yMarkValues = stride(from: minY, through: maxY, by: max(stepSize, .ulpOfOne)).map{ $0 }
        
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
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(values: yMarkValues)
        }
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
