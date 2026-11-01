import CarpoolKit
import CarpoolUI
import PhotosUI
import SwiftUI
import UIKit

/// Schaden melden: Foto (Kamera oder Mediathek), Text, „fahrbereit ja/nein".
struct DamageReportSheet: View {
    let store: FamilyStore
    let car: Car

    @State private var description = ""
    @State private var drivable = true
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var isSaving = false
    @State private var reported = false
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack {
                    Text("Schaden melden").sheetTitleStyle().accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Abbrechen") { dismiss() }.foregroundStyle(Color.inkSecondary)
                }
                Text(car.title).metaStyle()
                photoSection
                VStack(alignment: .leading, spacing: 6) {
                    Text("Was ist passiert?").sectionLabelStyle()
                    TextField("z. B. Kratzer an der Stoßstange hinten", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($textFocused)
                        .padding(Spacing.m)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card,
                                                                        style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Color.hairlineStrong, lineWidth: ControlSize.hairline))
                        .accessibilityIdentifier("damage.description")
                }
                FormCard {
                    Toggle("Fahrbereit", isOn: $drivable)
                        .tint(Color.statusFree)
                        .formFieldStyle()
                }
                if !drivable {
                    Text("Das Auto bekommt ein Warnzeichen, damit alle es sehen.")
                        .font(.callout).foregroundStyle(Color.danger)
                }
                Button("Melden", action: save)
                    .buttonStyle(.carpoolPrimary)
                    .disabled(isSaving || !draft(photo: nil).isValid)
                    .accessibilityIdentifier("damage.submit")
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
        .onChange(of: pickerItem) { _, item in Task { await load(item) } }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(image: $photo).ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: reported)
        .storeErrorAlert(store)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { self.photo = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .padding(Spacing.xs)
                            .accessibilityLabel("Foto entfernen")
                    }
                    .accessibilityLabel("Foto vom Schaden")
            }
            HStack(spacing: Spacing.xs) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showsCamera = true } label: { Label("Kamera", systemImage: "camera") }
                        .buttonStyle(.carpoolSecondary)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(photo == nil ? "Foto wählen" : "Anderes Foto", systemImage: "photo")
                }
                .buttonStyle(.carpoolSecondary)
            }
        }
    }

    private func draft(photo: Data?) -> DamageReport {
        DamageReport(carID: car.id, description: description, drivable: drivable, photo: photo)
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        photo = UIImage(data: data)
    }

    private func save() {
        let report = draft(photo: photo.flatMap(ImageCompressor.jpeg))
        isSaving = true
        Task {
            let ok = await store.perform { [familyID = car.familyId] in
                try await $0.reportDamage(report, familyID: familyID)
            }
            isSaving = false
            if ok {
                reported = true
                dismiss()
            }
        }
    }
}

/// Schaden ansehen: großes Foto, Text, Melder; „Erledigt" schließt ihn.
struct DamageDetailSheet: View {
    let store: FamilyStore
    let row: CarDetailState.DamageRow

    @State private var confirmsResolve = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if row.damage.photoPath != nil {
                    DamagePhoto(store: store, path: row.damage.photoPath, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(row.damage.description).sheetTitleStyle()
                    Text(row.meta).font(.callout)
                        .foregroundStyle(row.damage.drivable ? Color.inkMuted : Color.danger)
                }
                Button("Erledigt") { confirmsResolve = true }
                    .buttonStyle(.carpoolSecondary)
                    .accessibilityIdentifier("damage.resolve")
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, Spacing.l)
        }
        .background(Color.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Schaden als erledigt markieren?", isPresented: $confirmsResolve,
                            titleVisibility: .visible) {
            Button("Erledigt") {
                Task {
                    if await store.perform({ [id = row.damage.id] in try await $0.resolveDamage(id) }) { dismiss() }
                }
            }
        }
        .storeErrorAlert(store)
    }
}

/// Lädt ein Schadenfoto aus dem privaten Bucket; ohne Foto ein Kamera-Symbol.
struct DamagePhoto: View {
    let store: FamilyStore
    let path: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.hairline
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed || path == nil {
                Image(systemName: path == nil ? "camera" : "photo.badge.exclamationmark")
                    .foregroundStyle(Color.inkMuted)
            } else {
                ProgressView()
            }
        }
        .accessibilityLabel(path == nil ? "kein Foto" : "Foto vom Schaden")
        .task(id: path) {
            guard let path, image == nil else { return }
            if let data = try? await store.api.damagePhoto(path: path), let loaded = UIImage(data: data) {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

/// Verkleinert Fotos vor dem Hochladen (max. 1600 px, JPEG 0,7), damit der Bucket klein bleibt.
enum ImageCompressor {
    static let maxDimension: CGFloat = 1600
    static let quality: CGFloat = 0.7

    static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// Kamera über UIKit (SwiftUI hat keine eigene Kamera-Ansicht).
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
