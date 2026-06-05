extension UsageMenuCardView.Model {
    func heightFingerprint(section: String, additional: [String] = []) -> String {
        MenuCardHeightFingerprint.join([
            "section=\(section)",
            "provider=\(self.provider.rawValue)",
            "name=\(self.providerName)",
            "email=\(self.email)",
            "subtitle=\(self.subtitleText)",
            "subtitleStyle=\(self.subtitleStyle.heightFingerprint)",
            "plan=\(self.planText ?? "")",
            "placeholder=\(self.placeholder ?? "")",
            "credits=\(self.creditsText ?? "")",
            "creditsHint=\(self.creditsHintText ?? "")",
            "creditsCopy=\(self.creditsHintCopyText ?? "")",
            "metrics=\(MenuCardHeightFingerprint.join(self.metrics.map(\.heightFingerprint)))",
            "notes=\(MenuCardHeightFingerprint.join(self.usageNotes))",
            "dashboard=\(self.inlineUsageDashboard?.heightFingerprint ?? "")",
            "providerCost=\(self.providerCost?.heightFingerprint ?? "")",
            "tokenUsage=\(self.tokenUsage?.heightFingerprint ?? "")",
            "openaiAPI=\(self.openAIAPIUsage == nil ? "0" : "1")",
        ] + additional)
    }
}

private enum MenuCardHeightFingerprint {
    static func join(_ values: [String]) -> String {
        values.map { "\($0.count):\($0)" }.joined(separator: "|")
    }
}

extension UsageMenuCardView.Model.SubtitleStyle {
    fileprivate var heightFingerprint: String {
        switch self {
        case .info: "info"
        case .loading: "loading"
        case .error: "error"
        }
    }
}

extension UsageMenuCardView.Model.Metric {
    fileprivate var heightFingerprint: String {
        MenuCardHeightFingerprint.join([
            self.id,
            self.title,
            self.percentLabel,
            self.statusText ?? "",
            self.resetText ?? "",
            self.detailText ?? "",
            self.detailLeftText ?? "",
            self.detailRightText ?? "",
            self.pacePercent == nil ? "pace=0" : "pace=1",
            self.paceOnTop ? "paceTop=1" : "paceTop=0",
            self.cardStyle ? "card=1" : "card=0",
            "markers=\(self.warningMarkerPercents.count)",
        ])
    }
}

extension UsageMenuCardView.Model.ProviderCostSection {
    fileprivate var heightFingerprint: String {
        MenuCardHeightFingerprint.join([
            self.title,
            self.spendLine,
            self.percentLine ?? "",
            self.percentUsed == nil ? "percent=0" : "percent=1",
        ])
    }
}

extension UsageMenuCardView.Model.TokenUsageSection {
    fileprivate var heightFingerprint: String {
        MenuCardHeightFingerprint.join([
            self.sessionLine,
            self.monthLine,
            self.hintLine ?? "",
            self.errorLine ?? "",
            self.errorCopyText ?? "",
        ])
    }
}

extension InlineUsageDashboardModel {
    fileprivate var heightFingerprint: String {
        MenuCardHeightFingerprint.join([
            self.accessibilityLabel,
            self.valueStyle.heightFingerprint,
            MenuCardHeightFingerprint.join(self.kpis.map(\.heightFingerprint)),
            MenuCardHeightFingerprint.join(self.points.map(\.heightFingerprint)),
            MenuCardHeightFingerprint.join(self.detailLines),
        ])
    }
}

extension InlineUsageDashboardModel.KPI {
    fileprivate var heightFingerprint: String {
        MenuCardHeightFingerprint.join([
            self.title,
            self.value,
            self.emphasis ? "1" : "0",
        ])
    }
}

extension InlineUsageDashboardModel.Point {
    fileprivate var heightFingerprint: String {
        MenuCardHeightFingerprint.join([
            self.id,
            self.label,
            self.accessibilityValue,
        ])
    }
}

extension InlineUsageDashboardModel.ValueStyle {
    fileprivate var heightFingerprint: String {
        switch self {
        case .currencyUSD:
            "currencyUSD"
        case let .currency(symbol):
            "currency:\(symbol)"
        case .tokens:
            "tokens"
        }
    }
}
