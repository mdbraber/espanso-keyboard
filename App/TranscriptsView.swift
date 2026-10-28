import Charts
import SwiftUI

/// Everything you've dictated with Hex, newest first, grouped by day, with how much and how fast you talk.
struct TranscriptsView: View {
    private let store = Transcripts.shared
    @State private var query = ""
    @State private var confirmsDeleteAll = false

    static func controller() -> UIViewController {
        UIHostingController(rootView: TranscriptsView())
    }

    private var shown: [Transcript] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? store.all : store.all.filter { $0.text.localizedStandardContains(query) }
    }

    private var days: [(day: Date, transcripts: [Transcript])] {
        let calendar = Calendar.current
        var days: [(day: Date, transcripts: [Transcript])] = []
        for transcript in shown {
            let day = calendar.startOfDay(for: transcript.date)
            if days.last?.day == day { days[days.count - 1].transcripts.append(transcript) } else { days.append((day, [transcript])) }
        }
        return days
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, !store.all.isEmpty {
                    Section {
                        Summary(transcripts: store.all)
                    }
                }
                ForEach(days, id: \.day) { day in
                    Section(Self.title(of: day.day)) {
                        ForEach(day.transcripts) { transcript in
                            NavigationLink(value: transcript) { Row(transcript: transcript) }
                                .contextMenu { Actions(transcript: transcript) }
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) { store.delete([transcript.id]) }
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = transcript.text }
                                        .tint(.accentColor)
                                }
                        }
                    }
                }
            }
            .overlay {
                if store.all.isEmpty {
                    ContentUnavailableView {
                        Label("No Transcripts", systemImage: "waveform")
                    } description: {
                        Text("Tap the mic beside the keyboard's suggestions. Everything you dictate is saved here, on this iPhone.")
                    }
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Transcripts")
            .navigationDestination(for: Transcript.self) { TranscriptDetail(transcript: $0) }
            .searchable(text: $query)
            .toolbar {
                if !store.all.isEmpty {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Delete All", systemImage: "trash", role: .destructive) { confirmsDeleteAll = true }
                    }
                }
            }
            .confirmationDialog("Delete all \(store.all.count) transcripts from this iPhone?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { store.delete(Set(store.all.map(\.id))) }
            }
        }
    }

    private static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: day, to: .now).day, days < 7 { return day.formatted(.dateTime.weekday(.wide)) }
        let thisYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return thisYear ? day.formatted(.dateTime.weekday(.wide).month(.wide).day()) : day.formatted(date: .long, time: .omitted)
    }
}

private struct Row: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(transcript.text)
                .lineLimit(3)
                .foregroundStyle(transcript.typed ? .primary : .secondary)
            HStack(spacing: 6) {
                Text(transcript.date, format: .dateTime.hour().minute())
                Text("·")
                Text(Duration.seconds(transcript.seconds), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
                if !transcript.typed {
                    Text("·")
                    Label("Not typed", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                        .imageScale(.small)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct Actions: View {
    let transcript: Transcript

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = transcript.text }
        ShareLink(item: transcript.text)
        Button("Delete", systemImage: "trash", role: .destructive) { Transcripts.shared.delete([transcript.id]) }
    }
}

/// How much you've dictated: words, time talking and pace overall, and words per day for the last two weeks.
private struct Summary: View {
    let transcripts: [Transcript]

    private struct Day: Identifiable {
        var date: Date
        var words: Int
        var id: Date { date }
    }

    private var words: Int { transcripts.reduce(0) { $0 + $1.words } }
    private var seconds: Double { transcripts.reduce(0) { $0 + $1.seconds } }

    private var fortnight: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var words: [Date: Int] = [:]
        for transcript in transcripts { words[calendar.startOfDay(for: transcript.date), default: 0] += transcript.words }
        return (0 ..< 14).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map { Day(date: $0, words: words[$0] ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Stat(title: "Words", value: words.formatted())
                Stat(title: "Talking", value: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)))
                Stat(title: "Pace", value: seconds >= 1 ? "\(Int((Double(words) / seconds * 60).rounded())) wpm" : "–")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Words a day, last 2 weeks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Chart(fortnight) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.words), width: .ratio(0.62))
                        .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .clipShape(.rect(cornerRadius: 3))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranscriptDetail: View {
    let transcript: Transcript
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false

    var body: some View {
        List {
            Section {
                Text(transcript.text)
                    .font(.title3)
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
            }
            Section {
                LabeledContent("Said", value: transcript.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Length", value: Duration.seconds(transcript.seconds).formatted(.time(pattern: .minuteSecond)))
                LabeledContent("Words", value: transcript.words.formatted())
                if transcript.seconds >= 1 {
                    LabeledContent("Pace", value: "\(Int((Double(transcript.words) / transcript.seconds * 60).rounded())) wpm")
                }
                LabeledContent("Typed", value: transcript.typed ? "Yes" : "No, you tapped ✕")
            }
            Section {
                Button("Delete Transcript", role: .destructive) { confirmsDelete = true }
            }
        }
        .navigationTitle(transcript.date.formatted(.dateTime.hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = transcript.text }
                ShareLink(item: transcript.text)
            }
        }
        .confirmationDialog("Delete this transcript?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Transcripts.shared.delete([transcript.id])
                dismiss()
            }
        }
    }
}
