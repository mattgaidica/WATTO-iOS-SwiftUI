import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject private var bleManager = BLEManager()

    var body: some View {
        VStack {
            plotView(title: "Voltage", data: bleManager.voltageData)
            plotView(title: "Current", data: bleManager.currentData)
            plotView(title: "Power", data: bleManager.powerData)
        }
        .navigationBarTitle("My Charts", displayMode: .inline)
    }
    
    private func plotView(title: String, data: [Float]) -> some View {
        List {
            Section {
                Text(title)
                DataPlot(title: title, data: data)
                    .frame(height: 150)
            }
        }
    }
}

struct DataPlot: View {
    let title: String
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
                .accessibilityLabel("\(title) Line Series")
                .accessibilityValue("X: \(index), Y: \(data[index])")
                .accessibilityHidden(false)
            }
            .foregroundStyle(.red)
        }
        .accessibilityChartDescriptor(self)
        .chartYAxis(.automatic)
        .chartXAxis(.automatic)
    }
}

// MARK: - Accessibility
extension DataPlot: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let lineMin = data.min() ?? 0
        let lineMax = data.max() ?? 0
        let ymin = lineMin
        let ymax = lineMax
        
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
            name: "\(title) data series",
            isContinuous: true,
            dataPoints: data.enumerated().map {
                .init(x: Double($0.offset), y: Double($0.element))
            }
        )
        
        return AXChartDescriptor(
            title: "\(title) data",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [lineSeries]
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
