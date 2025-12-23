import Foundation

struct AppConfig {
    let firebaseApiKey: String
    let firebaseProjectId: String
    let firebaseAppId: String
    let firebaseSenderId: String
    let firebaseDatabaseUrl: String
    let weatherApiKey: String
    let weatherEndpoint: String

    static func load() -> AppConfig {
        let env = EnvLoader.load()
        return AppConfig(
            firebaseApiKey: env["FIREBASE_API_KEY"] ?? "",
            firebaseProjectId: env["FIREBASE_PROJECT_ID"] ?? "",
            firebaseAppId: env["FIREBASE_APP_ID_IOS"] ?? "",
            firebaseSenderId: env["FIREBASE_SENDER_ID"] ?? "",
            firebaseDatabaseUrl: env["FIREBASE_DATABASE_URL"] ?? "",
            weatherApiKey: env["WEATHER_API_KEY"] ?? "",
            weatherEndpoint: env["WEATHER_ENDPOINT"] ?? "https://api.weatherapi.com/v1"
        )
    }
}
