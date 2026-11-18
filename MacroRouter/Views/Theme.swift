import SwiftUI
import MacroCore

/// Shared colors, gradients and small building blocks used across the app.
enum Theme {
    /// Brand colors.
    static let blue = Color(red: 0.16, green: 0.43, blue: 0.96)
    static let cyan = Color(red: 0.04, green: 0.64, blue: 0.90)
    /// "Good / done": within target, saved, eaten, on track.
    static let success = Color(red: 0.16, green: 0.72, blue: 0.45)

    /// The app's signature gradient: buttons, hero cards, the login screen.
    static let brandGradient = LinearGradient(colors: [blue, cyan],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cornerRadius: CGFloat = 18

    /// Near-black with a hint of blue, behind every screen.
    static let background = Color(red: 0.03, green: 0.04, blue: 0.065)
}

// MARK: - Macro colors

extension MacroKind {
    var color: Color {
        switch self {
        case .protein: return Color(red: 0.95, green: 0.35, blue: 0.40)   // coral
        case .carbs: return Color(red: 0.97, green: 0.64, blue: 0.11)     // amber
        case .fat: return Color(red: 0.18, green: 0.80, blue: 0.62)       // mint (blue is the brand color)
        case .calories: return Color(red: 0.56, green: 0.39, blue: 0.95)  // violet
        }
    }

    var symbol: String {
        switch self {
        case .protein: return "dumbbell.fill"
        case .carbs: return "leaf.fill"
        case .fat: return "drop.fill"
        case .calories: return "flame.fill"
        }
    }

    var letter: String {
        switch self {
        case .protein: return "P"
        case .carbs: return "C"
        case .fat: return "F"
        case .calories: return "kcal"
        }
    }
}

extension IngredientCategory {
    var emoji: String {
        switch self {
        case .protein: return "🍗"
        case .carb: return "🍚"
        case .fat: return "🥑"
        }
    }

    var color: Color {
        switch self {
        case .protein: return MacroKind.protein.color
        case .carb: return MacroKind.carbs.color
        case .fat: return MacroKind.fat.color
        }
    }
}

extension Ingredient {
    /// A food-specific emoji when the name gives it away, otherwise the category's.
    var emoji: String {
        // Oils first, so "Oil, corn, peanut, and olive" isn't shown as corn.
        if nameHas("^oil") { return "🫗" }
        let name = self.name.lowercased()
        let table: [(keys: [String], emoji: String)] = [
            (["egg"], "🥚"), (["chicken", "turkey"], "🍗"), (["beef", "steak", "pork", "lamb", "bison"], "🥩"),
            (["bacon"], "🥓"), (["salmon", "tuna", "cod", "tilapia", "fish"], "🐟"), (["shrimp", "prawn"], "🦐"),
            (["tofu", "tempeh"], "🫘"), (["bean", "lentil", "chickpea"], "🫘"),
            (["yogurt", "yoghurt", "milk", "whey"], "🥛"), (["cheese", "cottage"], "🧀"),
            (["rice"], "🍚"), (["oat"], "🥣"), (["pasta", "spaghetti", "noodle"], "🍝"),
            (["bread", "toast", "bagel"], "🍞"), (["sweet potato", "yam"], "🍠"), (["potato"], "🥔"),
            (["broccoli"], "🥦"), (["spinach", "lettuce", "kale", "salad"], "🥬"), (["carrot"], "🥕"),
            (["corn"], "🌽"), (["banana"], "🍌"), (["apple"], "🍎"), (["berr"], "🫐"), (["orange"], "🍊"),
            (["avocado"], "🥑"), (["olive"], "🫒"), (["butter"], "🧈"), (["peanut", "almond", "nut", "cashew"], "🥜"),
            (["oil"], "🫗"),
        ]
        return table.first { entry in entry.keys.contains { name.contains($0) } }?.emoji ?? category.emoji
    }
}

// MARK: - Backgrounds

/// A soft green wash at the top of each screen instead of flat grey.
struct ThemedBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            // Soft blue glow at the top of the screen.
            LinearGradient(colors: [Theme.blue.opacity(0.28), Theme.cyan.opacity(0.10), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Lists and forms drawn over the themed background.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(ThemedBackground())
    }
}

// MARK: - Components

/// Big gradient capsule used for the main action on a screen.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                Capsule().fill(isEnabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.45)))
            }
            .shadow(color: isEnabled ? Theme.blue.opacity(0.35) : .clear, radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small colored capsule such as "P 31g".
struct MacroPill: View {
    let kind: MacroKind
    let value: Double

    var body: some View {
        Text(kind == .calories
             ? "\(Int(value.rounded())) kcal"
             : "\(kind.letter) \(MacroFormat.number(value))g")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(kind.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(kind.color.opacity(0.14), in: Capsule())
    }
}

/// Protein, carbs, fat and calories as a row of pills.
struct MacroPills: View {
    let macros: Macros
    var showCalories = true

    var body: some View {
        HStack(spacing: 4) {
            MacroPill(kind: .protein, value: macros.protein)
            MacroPill(kind: .carbs, value: macros.carbs)
            MacroPill(kind: .fat, value: macros.fat)
            if showCalories {
                MacroPill(kind: .calories, value: macros.calories)
            }
        }
    }
}

/// Colored rounded-square icon, like the ones in Settings.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Emoji on a tinted circle, used for foods.
struct EmojiBadge: View {
    let ingredient: Ingredient
    var size: CGFloat = 40

    private var category: IngredientCategory { ingredient.category }

    var body: some View {
        Text(ingredient.emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(category.color.opacity(0.16), in: Circle())
    }
}

/// Progress ring with the achieved value in the middle.
struct MacroRing: View {
    let kind: MacroKind
    let achieved: Double
    let target: Double
    var lineWidth: CGFloat = 9

    @State private var shown: Double = 0

    private var progress: Double { target > 0 ? min(achieved / target, 1) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(kind.color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(kind.color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(achieved.rounded()))")
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                Text(kind.unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { shown = progress }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { shown = new }
        }
    }
}
