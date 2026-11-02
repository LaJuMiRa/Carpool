import SwiftUI

/// Schlüsselbrett aus dem Splash (F01) und dem App-Icon: Brett mit zwei Schrauben,
/// drei Haken, drei Schlüssel. Winkel und Versatz kommen von außen (`SplashPose`).
public struct KeyBoardScene: View {
    /// Maße in Punkten; die Szene ist fest gezeichnet und wird bei Bedarf skaliert.
    public static let size = CGSize(width: 280, height: 132)
    static let boardHeight: CGFloat = 16
    static let hookLength: CGFloat = 12
    static let hookX: [CGFloat] = [70, 140, 210]

    private let pose: SplashPose

    public init(pose: SplashPose = .rest) {
        self.pose = pose
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            board
            ForEach(Self.hookX.indices, id: \.self) { index in
                hook.position(x: Self.hookX[index], y: Self.boardHeight + Self.hookLength / 2 - 2)
            }
            key(.oval, angle: pose.leftAngle, x: Self.hookX[0])
            key(.square, angle: pose.middleAngle, x: Self.hookX[1])
                .offset(y: pose.middleDrop)
                .opacity(pose.middleOpacity)
            key(.slim, angle: pose.rightAngle, x: Self.hookX[2])
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var board: some View {
        RoundedRectangle(cornerRadius: Radius.small)
            .fill(Color.hairline)
            .frame(width: Self.size.width, height: Self.boardHeight)
            .overlay {
                HStack {
                    screw
                    Spacer()
                    screw
                }
                .padding(.horizontal, Spacing.s)
            }
    }

    private var screw: some View {
        Circle().fill(Color.hairlineStrong).frame(width: 5, height: 5)
    }

    private var hook: some View {
        Capsule().fill(Color.inkMuted).frame(width: 2, height: Self.hookLength)
    }

    /// Der Schlüssel hängt mit dem Ring am Hakenende und pendelt um diesen Punkt.
    private func key(_ fob: KeyShape.Fob, angle: Double, x: CGFloat) -> some View {
        KeyShape(fob: fob)
            .rotationEffect(.degrees(angle), anchor: .top)
            .position(x: x, y: Self.boardHeight + Self.hookLength - KeyShape.ringSize / 2 + KeyShape.height / 2)
    }
}

/// Ein Schlüssel: Ring, Anhänger (drei Formen wie im Mockup), Bart mit Zähnen.
struct KeyShape: View {
    enum Fob {
        case oval, square, slim

        var size: CGSize {
            switch self {
            case .oval: CGSize(width: 30, height: 40)
            case .square: CGSize(width: 30, height: 38)
            case .slim: CGSize(width: 24, height: 42)
            }
        }

        var radius: CGFloat {
            switch self {
            case .oval: 15
            case .square: 6
            case .slim: 10
            }
        }
    }

    static let ringSize: CGFloat = 20
    static let bladeHeight: CGFloat = 34
    static let height: CGFloat = ringSize - 6 + 42 - 4 + bladeHeight

    let fob: Fob

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .stroke(Color.ink, lineWidth: 3)
                .frame(width: Self.ringSize - 3, height: Self.ringSize - 3)
                .frame(width: Self.ringSize, height: Self.ringSize)
                .zIndex(1)
            RoundedRectangle(cornerRadius: fob.radius)
                .fill(Color.ink)
                .overlay(alignment: .top) {
                    Circle().fill(Color.inkMuted).frame(width: 6, height: 6).padding(.top, 10)
                }
                .frame(width: fob.size.width, height: fob.size.height)
                .padding(.top, -6)
            blade.padding(.top, -4)
        }
        .frame(height: Self.height, alignment: .top)
    }

    private var blade: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.inkMuted)
            .frame(width: 7, height: Self.bladeHeight)
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 3) {
                    tooth
                    tooth
                }
                .offset(x: 4, y: -7)
            }
    }

    private var tooth: some View {
        Rectangle().fill(Color.inkMuted).frame(width: 4, height: 3)
    }
}
