import Foundation

/// What drinking enough water does, limited to claims with good evidence behind them.
struct Benefit: Identifiable {
    let id: String
    let symbol: String
    /// One sentence for the lock screen and the Why Water page.
    let fact: String
    /// A few words for the bottle's caption after you finish one.
    let short: String
    let source: String
    /// Hours of the day this one fits best, if any.
    var hours: Range<Int>? = nil

    static let all: [Benefit] = [
        Benefit(id: "focus", symbol: "brain.head.profile",
                fact: "Losing just 1–2% of your body’s water is linked to worse attention, more fatigue, and a lower mood.",
                short: "good for focus",
                source: "Riebl & Davy, ACSM’s Health & Fitness Journal, 2013"),
        Benefit(id: "slump", symbol: "sun.max",
                fact: "An afternoon slump can be mild dehydration as much as tiredness.",
                short: "ready for the afternoon",
                source: "Riebl & Davy, ACSM’s Health & Fitness Journal, 2013",
                hours: 13..<17),
        Benefit(id: "headache", symbol: "bandage",
                fact: "Dehydration is a common headache trigger, and drinking water often eases it.",
                short: "helps keep headaches away",
                source: "Blau, Kell & Sperling, Cephalalgia, 2004"),
        Benefit(id: "kidneys", symbol: "drop.circle",
                fact: "Drinking more water is one of the best-proven ways to prevent kidney stones.",
                short: "kind to your kidneys",
                source: "American Urological Association guideline, 2014"),
        Benefit(id: "heat", symbol: "thermometer.sun",
                fact: "Sweat is how your body sheds heat, and it needs water to keep working when you’re active or it’s hot.",
                short: "helps you stay cool",
                source: "National Academies, Dietary Reference Intakes for Water, 2005"),
        Benefit(id: "digestion", symbol: "leaf",
                fact: "Enough water helps keep digestion regular and prevents constipation.",
                short: "good for digestion",
                source: "Anti et al., Hepato-Gastroenterology, 1998"),
        Benefit(id: "bladder", symbol: "cross.vial",
                fact: "In a trial, women prone to bladder infections who drank an extra 1.5 L a day had about half as many.",
                short: "good for your bladder",
                source: "Hooton et al., JAMA Internal Medicine, 2018"),
        Benefit(id: "meals", symbol: "fork.knife",
                fact: "A glass of water before a meal can help you feel full sooner.",
                short: "helps you feel full",
                source: "Dennis et al., Obesity, 2010",
                hours: 11..<13),
    ]

    /// Changes with each bottle and each day, preferring a fact that fits the time of day.
    static func pick(at date: Date, bottle: Int) -> Benefit {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        if let timely = all.first(where: { $0.hours?.contains(hour) ?? false }), bottle.isMultiple(of: 2) {
            return timely
        }
        let general = all.filter { $0.hours == nil }
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        return general[(day * 3 + bottle) % general.count]
    }
}
