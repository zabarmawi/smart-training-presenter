import SwiftUI
import PDFKit

struct SharedPresentationView:View {
    @ObservedObject var presentation:SharedPresentation
    @ObservedObject private var appearance=UIAppearance.shared
    var body:some View {
        VStack(spacing:0) {
            if let document=presentation.document {
                ZStack {
                    SharedSlideCanvas(document:document,page:presentation.page,surround:appearance.theme.surround,onRaster:{image,page,doc in presentation.accept(image,page:page,document:doc)})
                    if presentation.preparedImage==nil {Text("تجهيز العرض التقديمي…").foregroundColor(.white)}
                }.allowsHitTesting(false)
                    .environment(\.layoutDirection,.leftToRight).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {Text("بانتظار العرض التقديمي").font(.title).frame(maxWidth:.infinity,maxHeight:.infinity)}
            if let timer=presentation.timer {
                Divider()
                HStack {Text("وقت النشاط");Spacer();Text(timer).font(.system(size:30,weight:.semibold,design:.monospaced)).environment(\.layoutDirection,.leftToRight)}
                    .padding(12).background(appearance.theme.accent.opacity(0.08)).accessibilityIdentifier("participantTimer")
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:appearance.theme.surround)).preferredColorScheme(appearance.theme.darkMode ? .dark:.light).environment(\.layoutDirection,.rightToLeft)
    }
}
struct ShareControls:View {
    @ObservedObject var sharing:SharingSession
    var body:some View {
        HStack(spacing:5) {
            Button(sharing.isOpen ? "إغلاق نافذة المشاركة":"فتح نافذة المشاركة") {
                if sharing.isOpen {sharing.close()} else {sharing.open()}
            }.trainerHelp(sharing.isOpen ? "إغلاق نافذة المشاركة":"فتح نافذة المشاركة").accessibilityIdentifier("toggleSharedPresentation")
            Menu {
                Picker("وضع الشاشة",selection:Binding(get:{sharing.preferences.mode},set:{sharing.setMode($0)})) {
                    ForEach(SharingMode.allCases,id:\.self){Text($0.rawValue).tag($0)}
                }
                Text("الشاشات الفعلية: \(sharing.screenCount) · \(sharing.effectiveMode.rawValue)")
                Button("تكبير نافذة المشاركة",action:sharing.maximize).disabled(!sharing.isOpen)
                Button("أدوات المدرب",action:sharing.showTrainer).disabled(!sharing.isOpen)
                if sharing.effectiveMode == .dual {Button("ملء شاشة المشاركة"){sharing.windowState.toggle()}.disabled(!sharing.isOpen)}
                Divider()
                Toggle("إظهار مؤقت النشاط للمشاركين",isOn:$sharing.preferences.showTimer).accessibilityIdentifier("shareActivityTimer")
                Toggle("إظهار الزمن الإضافي للمشاركين",isOn:$sharing.preferences.showOvertime)
                Toggle("كتم صوت المؤقت أثناء فتح المشاركة",isOn:$sharing.preferences.muteSound)
            } label:{Image(systemName:"display.2")}.fixedSize().trainerHelp("تبديل وضع الشاشة وخيارات المشاركة").accessibilityLabel("وضع الشاشة وخيارات المشاركة")
        }.onChange(of:sharing.preferences.showTimer){_ in sharing.save()}
         .onChange(of:sharing.preferences.showOvertime){_ in sharing.save()}
         .onChange(of:sharing.preferences.muteSound){_ in sharing.save()}
    }
}
struct AudienceSizingControls:View {
    @ObservedObject var sharing:SharingSession
    var body:some View {
        HStack(spacing:6) {
            if sharing.isOpen {
                Button("تكبير الجمهور",action:sharing.toggleMaximize).trainerHelp("تكبير نافذة الجمهور وحدها أو استعادة حجمها").accessibilityIdentifier("zoomAudience")
                Button {sharing.showControls()} label:{Image(systemName:"switch.2")}.trainerHelp("أدوات تحكم خاصة أثناء المشاركة").accessibilityIdentifier("showShareControls")
            }
        }
    }
}
struct SharingHint:View {
    @ObservedObject var sharing:SharingSession
    var body:some View {
        if sharing.isOpen {
            Text("\(sharing.effectiveMode.rawValue) · \(sharing.screenCount) شاشة فعلية. Teams: شارك Shared Presentation فقط؛ مشاركة سطح المكتب قد تكشف أدواتك. لا تصغّر النافذة أو تخفِ التطبيق أثناء المشاركة.")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal,10).padding(.bottom,4)
                .accessibilityIdentifier("trainerSharingHint")
        }
    }
}
