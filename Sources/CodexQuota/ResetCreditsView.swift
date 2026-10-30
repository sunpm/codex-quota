import SwiftUI
import QuotaCore

struct ResetCreditsView: View {
    let credits: RateLimitResetCredits

    var body: some View {
        let available = credits.availableCredits
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("重置卡").font(.headline)
                Spacer()
                Text("\(credits.availableCount) 张可用").monospacedDigit()
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(available) { credit in
                        HStack {
                            Text(credit.expirationDate.map { $0 <= context.date } == true ? "已到期" : "到期")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let expiration = credit.expirationDate {
                                Text(expiration.formatted(.dateTime.year().month().day().hour().minute()))
                                    .monospacedDigit()
                            } else {
                                Text("无到期时间").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if credits.availableCount > UInt(available.count) {
                Text(available.isEmpty ? "到期时间暂不可用" : "部分重置卡未返回到期明细")
                    .font(PanelTypography.detail).foregroundStyle(.secondary)
            }
        }.font(.system(size: 13))
    }
}
