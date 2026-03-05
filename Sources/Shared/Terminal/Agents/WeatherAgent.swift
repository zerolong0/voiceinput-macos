import Foundation

final class WeatherAgent: VoiceAgentPlugin {
    var intentTypes: [IntentType] { [.weather] }

    private struct WttrResponse: Decodable {
        struct CurrentCondition: Decodable {
            let temp_C: String
            let weatherDesc: [WeatherDesc]
            let humidity: String
            let windspeedKmph: String
            let FeelsLikeC: String?
        }
        struct WeatherDesc: Decodable {
            let value: String
        }
        let current_condition: [CurrentCondition]
    }

    func execute(intent: RecognizedIntent) async -> AgentResponse {
        let city = intent.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedCity = city.isEmpty || city == "auto"
            ? ""
            : (city.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? city)

        let urlString = encodedCity.isEmpty
            ? "https://wttr.in/?format=j1"
            : "https://wttr.in/\(encodedCity)?format=j1"

        guard let url = URL(string: urlString) else {
            return .simple("无法构建天气 URL", success: false)
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("VoiceInputApp/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .simple("天气服务暂时不可用", success: false)
            }

            guard let weather = try? JSONDecoder().decode(WttrResponse.self, from: data),
                  let condition = weather.current_condition.first else {
                return .simple("无法解析天气数据", success: false)
            }

            let desc = condition.weatherDesc.first?.value ?? "未知"
            let tempC = condition.temp_C
            let humidity = condition.humidity
            let wind = condition.windspeedKmph
            let feels = condition.FeelsLikeC ?? tempC

            let locationLabel = city.isEmpty || city == "auto" ? "当前位置" : city
            let body = """
            温度: \(tempC)°C（体感 \(feels)°C）
            天气: \(desc)
            湿度: \(humidity)%
            风速: \(wind) km/h
            """

            return AgentResponse(
                success: true,
                title: "\(locationLabel)天气: \(tempC)°C \(desc)",
                body: body,
                actions: [],
                contentType: .keyValue
            )
        } catch {
            return .simple("天气查询失败: \(error.localizedDescription)", success: false)
        }
    }
}
