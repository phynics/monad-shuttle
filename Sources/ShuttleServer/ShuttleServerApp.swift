public enum ShuttleServerApp {
    public static func makeStartupBanner() -> String {
        "ShuttleServer bootstrap ready"
    }

    public static func main() {
        print(makeStartupBanner())
    }
}
